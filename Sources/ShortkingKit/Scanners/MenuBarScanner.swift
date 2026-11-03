import ApplicationServices
import Foundation
import ShortkingCore

/// Reads the menu key equivalents of every running app via the Accessibility API.
///
/// This is the slow part of any scan, so results are cached per
/// `(bundleID, version)` — a cache key that invalidates itself when the app
/// updates. Menus are never expanded, only read: pressing them makes dynamic items
/// (Recent Files, Window lists) churn and would make the cache worthless.
///
/// Coverage caveat, surfaced honestly in the UI: this only sees *running* apps, and
/// Electron/Qt/Java hosts expose menus inconsistently.
public final class MenuBarScanner: ClaimSource {

    public let identifier = "menus"
    public let displayName = "Menu bar shortcuts"
    public let requirement: ScanRequirement = .accessibility

    private let cache: MenuCache

    public init(cache: MenuCache = MenuCache()) {
        self.cache = cache
    }

    public func isEnabled(for options: ScanOptions) -> Bool {
        options.includeMenus
    }

    public func scan(context: ScanContext) async throws -> [Claim] {
        guard AXBridge.isTrusted else {
            throw ScanError.missingPermission(.accessibility)
        }

        var targets = context.runningApps.filter(\.hasMenuBar)
        if context.options.menusForFrontmostOnly {
            targets = targets.filter(\.isActive)
        }

        // Persist completed apps even if a later app times out or is cancelled.
        defer { cache.flush() }

        var claims: [Claim] = []
        for app in targets {
            if Task.isCancelled { break }
            claims.append(contentsOf: makeClaims(for: app))
        }
        return claims
    }

    private func makeClaims(for app: RunningApp) -> [Claim] {
        let entries: [MenuEntry]
        if let cached = cache.entries(forKey: app.cacheKey) {
            entries = cached
        } else {
            guard let completed = walk(app: app).cacheableEntries else { return [] }
            entries = completed
            cache.store(entries, forKey: app.cacheKey)
        }

        let owner = app.owner
        return entries.map { entry in
            Claim(
                combo: entry.combo,
                layer: .appMenu,
                status: .known,
                owner: owner,
                label: entry.title,
                enabled: entry.enabled,
                evidence: [
                    Evidence(
                        kind: .accessibilityMenu,
                        summary: entry.menuPath.joined(separator: " ▸ "),
                        detail: [
                            "bundleID": owner.bundleID ?? "—",
                            "menuPath": entry.menuPath.joined(separator: " ▸ "),
                        ]
                    )
                ]
            )
        }
    }

    private func walk(app: RunningApp) -> MenuWalkResult<MenuEntry> {
        var budget = MenuWalkBudget()
        let reader = AXMenuReader(budget: budget)
        let element = AXBridge.application(
            pid: pid_t(app.pid), timeout: Float(MenuWalkBudget.messagingTimeout)
        )
        var entries: [MenuEntry] = []

        do {
            let menuBar = try reader.menuBar(of: element)
            for child in try reader.children(of: menuBar) {
                try recurse(element: child, path: [], depth: 0, reader: reader,
                    entries: &entries, budget: &budget)
            }
            _ = try budget.readTimeout()
            guard !budget.wasTruncated else { return .incomplete }
            return .complete(entries)
        } catch {
            // An unavailable or truncated menu must be retried on the next scan.
            return .incomplete
        }
    }

    private func recurse(
        element: AXUIElement,
        path: [String],
        depth: Int,
        reader: AXMenuReader,
        entries: inout [MenuEntry],
        budget: inout MenuWalkBudget
    ) throws {
        guard try budget.visit(depth: depth) else { return }

        let title = try reader.title(of: element)
        let currentPath = title.map { path + [$0] } ?? path

        if let combo = try reader.shortcut(of: element), !combo.isBare {
            let enabled = try reader.enabled(of: element)
            entries.append(
                MenuEntry(
                    combo: combo,
                    title: title ?? currentPath.last ?? "Menu item",
                    menuPath: currentPath,
                    enabled: enabled
                )
            )
        }

        for child in try reader.children(of: element) {
            try recurse(element: child, path: currentPath, depth: depth + 1, reader: reader,
                entries: &entries, budget: &budget)
        }
    }
}

/// One menu item that carries a key equivalent.
public struct MenuEntry: Codable, Hashable, Sendable {
    public var combo: KeyCombo
    public var title: String
    public var menuPath: [String]
    public var enabled: Bool

    public init(combo: KeyCombo, title: String, menuPath: [String], enabled: Bool) {
        self.combo = combo
        self.title = title
        self.menuPath = menuPath
        self.enabled = enabled
    }
}

/// Menu results keyed by `(bundleID, version)` with a TTL.
public final class MenuCache: @unchecked Sendable {

    private struct Entry: Codable {
        var entries: [MenuEntry]
        var storedAt: Date
    }

    private var storage: [String: Entry] = [:]
    private var isDirty = false
    private let lock = NSLock()
    private let ttl: TimeInterval
    private let persistence: JSONStore<[String: Entry]>?

    public init(ttl: TimeInterval = 60 * 60 * 24, persistent: Bool = true) {
        self.ttl = ttl
        self.persistence = persistent
            ? JSONStore(filename: "menu-cache.json", prettyPrinted: false)
            : nil
        if let loaded = persistence?.load() {
            storage = loaded
        }
    }

    public func entries(forKey key: String) -> [MenuEntry]? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = storage[key] else { return nil }
        guard Date().timeIntervalSince(entry.storedAt) < ttl else {
            storage[key] = nil
            isDirty = true
            return nil
        }
        return entry.entries
    }

    /// Records one app's menus in memory. Call ``flush()`` when the scan is done.
    public func store(_ entries: [MenuEntry], forKey key: String) {
        lock.lock()
        storage[key] = Entry(entries: entries, storedAt: Date())
        isDirty = true
        lock.unlock()
    }

    /// Persists the cache, once, if anything changed.
    ///
    /// This used to happen inside ``store(_:forKey:)``, which is called **once per
    /// running application** — so a cold scan on a machine with forty apps performed
    /// forty full JSON re-encodes and forty atomic file replacements of a document
    /// that grows to several megabytes. Quadratic in the number of running apps, all
    /// of it on the scan's critical path.
    ///
    /// Expired entries are dropped here too. They were only ever removed on read, so
    /// an app the user uninstalled a year ago kept its menus in the file forever.
    public func flush() {
        lock.lock()
        guard isDirty else {
            lock.unlock()
            return
        }
        let cutoff = Date().addingTimeInterval(-ttl)
        storage = storage.filter { $0.value.storedAt >= cutoff }
        let snapshot = storage
        isDirty = false
        lock.unlock()

        persistence?.save(snapshot)
    }

    public func clear() {
        lock.lock()
        storage = [:]
        isDirty = false
        lock.unlock()
        persistence?.save([:])
    }
}
