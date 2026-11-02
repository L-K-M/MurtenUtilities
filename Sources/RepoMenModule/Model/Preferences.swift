import Foundation
import Combine
import RepoMenCore

/// RepoMen's settings, persisted to the module's `UserDefaults` (the suite gives each
/// module its own domain, so the keys keep their standalone names) and observable
/// by SwiftUI. The provider owns the one instance.
final class Preferences: ObservableObject {
    private let defaults: UserDefaults

    private enum Key {
        static let scanRoots = "scanRoots"
        static let excludedPaths = "excludedPaths"
        static let moveToTrash = "moveToTrash"
        static let idleDays = "idleDays"
        static let disabledKinds = "disabledKinds"
        static let lifetimeReclaimedBytes = "lifetimeReclaimedBytes"
        static let lifetimeReclaimedCount = "lifetimeReclaimedCount"
        static let watchedFolders = "watchedFolders"
        static let scanAtLaunch = "scanAtLaunch"
        static let lastWatchRun = "lastWatchRun"
        static let autoTrashLog = "autoTrashLog"
    }

    /// Folders whose trees are deep-scanned for project artifacts (absolute paths).
    @Published var scanRoots: [String] {
        didSet { defaults.set(scanRoots, forKey: Key.scanRoots) }
    }

    /// Paths the user told us to never suggest again (absolute paths).
    @Published var excludedPaths: [String] {
        didSet { defaults.set(excludedPaths, forKey: Key.excludedPaths) }
    }

    /// Reclaim by moving to the Trash (default, reversible) instead of deleting.
    @Published var moveToTrash: Bool {
        didSet { defaults.set(moveToTrash, forKey: Key.moveToTrash) }
    }

    /// Age threshold (days) used by the "Select idle" quick action.
    @Published var idleDays: Int {
        didSet { defaults.set(idleDays, forKey: Key.idleDays) }
    }

    /// Kinds the user switched off in Settings → Rules (raw values).
    @Published var disabledKinds: Set<String> {
        didSet { defaults.set(Array(disabledKinds).sorted(), forKey: Key.disabledKinds) }
    }

    /// All-time repossession tally — every reclaim adds to it, nothing resets it.
    @Published var lifetimeReclaimedBytes: Int64 {
        didSet { defaults.set(Int(lifetimeReclaimedBytes), forKey: Key.lifetimeReclaimedBytes) }
    }
    @Published var lifetimeReclaimedCount: Int {
        didSet { defaults.set(lifetimeReclaimedCount, forKey: Key.lifetimeReclaimedCount) }
    }

    /// Directories RepoMen watches (Settings → Watch), JSON-encoded. The suite's
    /// background check reports on them; auto-trash runs only in folders the user
    /// armed one by one.
    @Published var watchedFolders: [WatchedFolder] {
        didSet {
            // set(nil) would silently delete the persisted value on an encode failure.
            if let data = try? JSONEncoder().encode(watchedFolders) {
                defaults.set(data, forKey: Key.watchedFolders)
            }
        }
    }

    /// Run one scan automatically when the pane first opens.
    @Published var scanAtLaunch: Bool {
        didSet { defaults.set(scanAtLaunch, forKey: Key.scanAtLaunch) }
    }

    /// The most recent auto-trash pass, for the menu section and Settings.
    @Published var lastWatchRun: WatchRunRecord? {
        didSet {
            if let data = try? JSONEncoder().encode(lastWatchRun) {
                defaults.set(data, forKey: Key.lastWatchRun)
            }
        }
    }

    /// What armed auto-trash moved to the Trash or left alone, newest first.
    @Published var autoTrashLog: [AutoTrashLogEntry] {
        didSet {
            if let data = try? JSONEncoder().encode(autoTrashLog) {
                defaults.set(data, forKey: Key.autoTrashLog)
            }
        }
    }

    /// Adds a folder to the watched set (deduped, inheriting the current idle
    /// threshold, auto-trash unarmed).
    func watchFolder(path: String) {
        guard !watchedFolders.contains(where: { $0.path == path }) else { return }
        watchedFolders.append(WatchedFolder(path: path, maxIdleDays: idleDays))
    }

    /// The settings the background check reads, snapshotted for one poll.
    var watchSettings: StaleWatchSettings {
        StaleWatchSettings(folders: watchedFolders, scanRoots: scanRoots, scanRootIdleDays: idleDays,
                           excludedPaths: Set(excludedPaths), enabledKinds: enabledKinds)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.scanRoots = defaults.stringArray(forKey: Key.scanRoots)
            ?? Self.defaultScanRoots()
        self.excludedPaths = defaults.stringArray(forKey: Key.excludedPaths) ?? []
        self.moveToTrash = defaults.object(forKey: Key.moveToTrash) as? Bool ?? true
        self.idleDays = defaults.object(forKey: Key.idleDays) as? Int ?? 30
        self.disabledKinds = Set(defaults.stringArray(forKey: Key.disabledKinds) ?? [])
        self.lifetimeReclaimedBytes = Int64(defaults.integer(forKey: Key.lifetimeReclaimedBytes))
        self.lifetimeReclaimedCount = defaults.integer(forKey: Key.lifetimeReclaimedCount)
        self.watchedFolders = (defaults.data(forKey: Key.watchedFolders)
            .flatMap { try? JSONDecoder().decode([WatchedFolder].self, from: $0) }) ?? []
        self.scanAtLaunch = defaults.object(forKey: Key.scanAtLaunch) as? Bool ?? false
        self.lastWatchRun = defaults.data(forKey: Key.lastWatchRun)
            .flatMap { try? JSONDecoder().decode(WatchRunRecord.self, from: $0) }
        self.autoTrashLog = defaults.data(forKey: Key.autoTrashLog)
            .flatMap { try? JSONDecoder().decode([AutoTrashLogEntry].self, from: $0) } ?? []
    }

    var enabledKinds: Set<ArtifactKind> {
        Set(ArtifactKind.allCases.filter { !disabledKinds.contains($0.rawValue) })
    }

    func isEnabled(_ kind: ArtifactKind) -> Bool {
        !disabledKinds.contains(kind.rawValue)
    }

    func setEnabled(_ enabled: Bool, kind: ArtifactKind) {
        if enabled {
            disabledKinds.remove(kind.rawValue)
        } else {
            disabledKinds.insert(kind.rawValue)
        }
    }

    /// The dev folders people actually use, filtered to those that exist — so a first
    /// scan finds code without any setup. Users refine the list in Settings → Folders.
    static func defaultScanRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                 fileManager: FileManager = .default) -> [String] {
        let candidates = [
            "Documents/GitHub", "Documents/GitLab", "Developer", "Projects", "projects",
            "Code", "code", "src", "repos", "git", "work", "dev",
        ]
        var roots: [String] = []
        var seenCanonical = Set<String>()
        for candidate in candidates {
            let url = home.appendingPathComponent(candidate)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            // fileExists is case-insensitive on default APFS, so probing "Projects"
            // AND "projects" finds the same physical folder twice — which used to
            // double every scan result. Dedupe on (and keep) the on-disk spelling.
            let canonical = (try? url.resourceValues(forKeys: [.canonicalPathKey]))?
                .canonicalPath ?? url.path
            guard seenCanonical.insert(canonical).inserted else { continue }
            roots.append(canonical)
        }
        // No recognizable dev folder: fall back to ~/Documents rather than nothing.
        if roots.isEmpty {
            let documents = home.appendingPathComponent("Documents")
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: documents.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                roots.append(documents.path)
            }
        }
        return roots
    }
}
