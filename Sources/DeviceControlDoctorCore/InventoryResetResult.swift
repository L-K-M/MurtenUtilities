import Foundation

/// What a confirmed inventory reset achieved, entry by entry, judged by
/// reading the databases again afterwards. `tccutil` reporting success is
/// not enough: a running app can ask again at once, and organization
/// policy can keep an entry in place.
public struct InventoryResetResult: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// The command succeeded and the entry is gone from a fresh read.
        case removed
        /// The command succeeded but the entry is still recorded.
        case stillRecorded
        /// `tccutil` did not report success; the detail is its answer.
        case failed(String)
        /// The command succeeded but its database could not be read again.
        case unverified
        /// Not something `tccutil` can reset; only System Settings can.
        case skipped
    }

    public struct Item: Identifiable, Sendable {
        public let entry: InventoryEntry
        public let outcome: Outcome
        public var id: String { entry.id }
    }

    public let items: [Item]

    public init(items: [Item]) { self.items = items }

    /// The key `commandFailures` uses for one command.
    public static func commandKey(bundleIdentifier: String, service: String) -> String {
        bundleIdentifier + "\u{1F}" + service
    }

    /// Judges each requested entry. `commandFailures` holds the failure of
    /// every command that did not report success, by `commandKey`; `after`
    /// is the fresh read, nil when there is none.
    public static func assess(requested: [InventoryEntry], skipped: [InventoryEntry],
                              commandFailures: [String: String], after: PermissionInventory?) -> InventoryResetResult {
        let remaining = Set(after?.entries.map(\.id) ?? [])
        let readable = Set(after?.sources.compactMap { source -> PermissionRecord.Database? in
            if case .read = source.reading { return source.database }
            return nil
        } ?? [])

        var items: [Item] = requested.map { entry in
            let key = commandKey(bundleIdentifier: entry.record.client, service: entry.service.resetName)
            if let failure = commandFailures[key] { return Item(entry: entry, outcome: .failed(failure)) }
            guard readable.contains(entry.record.database) else { return Item(entry: entry, outcome: .unverified) }
            return Item(entry: entry, outcome: remaining.contains(entry.id) ? .stillRecorded : .removed)
        }
        items += skipped.map { Item(entry: $0, outcome: .skipped) }
        return InventoryResetResult(items: items)
    }

    public func count(_ outcome: Outcome) -> Int {
        items.filter { $0.outcome == outcome }.count
    }

    public var failedCount: Int {
        items.filter { if case .failed = $0.outcome { return true }; return false }.count
    }

    /// Everything removed that was asked for, nothing left over.
    public var removedEverything: Bool { !items.isEmpty && count(.removed) == items.count }

    /// One sentence per kind of outcome, for the notice and the sheet.
    public var summary: String {
        var parts: [String] = []
        let removed = count(.removed)
        if removed > 0 { parts.append("Removed \(Self.entries(removed)).") }
        let still = count(.stillRecorded)
        if still > 0 {
            parts.append("\(Self.entries(still)) \(still == 1 ? "is" : "are") still recorded. A running app may have asked again, or your organization may manage \(still == 1 ? "it" : "them").")
        }
        if failedCount > 0 {
            parts.append("tccutil did not reset \(Self.entries(failedCount)).")
        }
        let unverified = count(.unverified)
        if unverified > 0 {
            parts.append("\(Self.entries(unverified)) could not be checked afterwards.")
        }
        let skipped = count(.skipped)
        if skipped > 0 {
            parts.append("\(Self.entries(skipped)) can only be removed in System Settings.")
        }
        return parts.isEmpty ? "Nothing was reset." : parts.joined(separator: " ")
    }

    private static func entries(_ count: Int) -> String {
        count == 1 ? "1 entry" : "\(count) entries"
    }
}
