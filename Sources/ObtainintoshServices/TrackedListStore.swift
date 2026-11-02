import Foundation
import ObtainintoshCore

/// The suite's own tracked list, persisted as JSON in the standalone app's
/// `apps.json` shape, without secrets: keys live in the Keychain.
///
/// Every change builds the proposed list, writes it, and only then adopts
/// it, so memory never runs ahead of disk when a write fails. The file is
/// owner-only and replaced atomically; a symbolic link or anything but a
/// regular file at its path is refused rather than followed, and an
/// unreadable file is preserved beside it before starting empty.
public final class TrackedListStore: @unchecked Sendable {
    /// What loading found.
    public enum LoadOutcome: Equatable, Sendable {
        case loaded
        case fresh
        /// The file could not be read; it was preserved at `backup`.
        case recovered(backup: URL, reason: String)
    }

    /// `~/Library/Application Support/MurtenUtilities/Obtainintosh/apps.json`.
    public static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("MurtenUtilities/Obtainintosh/apps.json")
    }

    public let fileURL: URL
    public let loadOutcome: LoadOutcome
    private let lock = NSLock()
    /// Guarded by `lock`.
    private var list: TrackedAppList

    /// Loads the list, creating its folder owner-only.
    public init(fileURL: URL = TrackedListStore.defaultURL) throws {
        self.fileURL = fileURL
        try PrivateFile.prepareDirectory(fileURL.deletingLastPathComponent())

        guard try Self.inspect(fileURL) else {
            list = TrackedAppList()
            loadOutcome = .fresh
            return
        }

        // A file written loosely by something else is tightened on the way in.
        try PrivateFile.tighten(fileURL)
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ObtainintoshError("Failed to read \(fileURL.lastPathComponent): \(error.localizedDescription)")
        }
        do {
            list = TrackedAppList(data: try JSONDecoder().decode(TrackedAppData.self, from: data))
            loadOutcome = .loaded
        } catch {
            // An unreadable file is no reason to refuse to open: preserve
            // the bytes, then carry on empty.
            let backup = try PrivateFile.backUpCorruptFile(fileURL)
            list = TrackedAppList()
            loadOutcome = .recovered(backup: backup, reason: error.localizedDescription)
        }
    }

    /// A store over given data, for tests: nothing is read.
    init(fileURL: URL, data: TrackedAppData) {
        self.fileURL = fileURL
        loadOutcome = .loaded
        list = TrackedAppList(data: data)
    }

    /// The list as last saved, read without writing anything: no folder
    /// creation, no permission change, no backup. nil when there is no file.
    /// The background check reads through this.
    public static func readSnapshot(at url: URL) throws -> TrackedAppData? {
        guard try inspect(url) else { return nil }
        return try JSONDecoder().decode(TrackedAppData.self, from: Data(contentsOf: url))
    }

    /// Whether a readable list file is at `url`, without reading it.
    static func readSnapshotAttributes(_ url: URL) throws -> Bool {
        try inspect(url)
    }

    /// Whether a regular file exists at `url`; throws for a symbolic link or
    /// anything else. Checks the entry itself, not what it points at.
    private static func inspect(_ url: URL) throws -> Bool {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            if FileManager.default.fileExists(atPath: url.path) || isDanglingLink(url) {
                throw ObtainintoshError("Failed to inspect \(url.lastPathComponent): \(error.localizedDescription)")
            }
            return false
        }
        let type = attributes[.type] as? FileAttributeType
        if type == .typeSymbolicLink {
            throw ObtainintoshError("Refusing to use \(url.lastPathComponent) because it is a symbolic link")
        }
        guard type == .typeRegular else {
            throw ObtainintoshError("Refusing to use \(url.lastPathComponent) because it is not a regular file")
        }
        return true
    }

    private static func isDanglingLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    // MARK: - Reading

    public var apps: [TrackedApp] {
        lock.withLock { list.apps }
    }

    public var data: TrackedAppData {
        lock.withLock { list.data }
    }

    public func app(id: String) -> TrackedApp? {
        lock.withLock { list.app(id: id) }
    }

    // MARK: - Changing

    /// Adds programs in one write, skipping those tracked already. Nothing
    /// is written when nothing is added.
    public func add(_ apps: [TrackedApp]) throws -> TrackedAppList.BatchAddition {
        try change { list in
            let addition = list.add(apps)
            return (addition, !addition.added.isEmpty)
        }
    }

    /// Adds one program, refusing one tracked already.
    public func addOne(_ app: TrackedApp) throws -> TrackedApp {
        try change { list in (try list.addOne(app), true) }
    }

    public func update(_ app: TrackedApp) throws {
        try change { list in
            try list.update(app)
            return ((), true)
        }
    }

    public func remove(id: String) throws {
        try change { list in
            list.remove(id: id)
            return ((), true)
        }
    }

    /// Clears the download records of the named programs, writing only when
    /// something changed.
    @discardableResult
    public func forgetDownloads(_ ids: [String]) throws -> Int {
        try change { list in
            let cleared = list.forgetDownloads(ids)
            return (cleared, cleared > 0)
        }
    }

    public func applyCheckResult(snapshot: TrackedApp, update: CheckOwnedUpdate) throws -> PendingResultApplication {
        try change { list in
            let application = list.applyCheckResult(snapshot: snapshot, update: update)
            return (application, application == .applied)
        }
    }

    /// Runs `body` on a copy, persists the copy when `body` says it changed,
    /// and adopts it only after the write succeeded.
    private func change<Value>(_ body: (inout TrackedAppList) throws -> (Value, Bool)) throws -> Value {
        try lock.withLock {
            var proposed = list
            let (result, changed) = try body(&proposed)
            guard changed else { return result }
            try persist(proposed.data)
            list = proposed
            return result
        }
    }

    private func persist(_ data: TrackedAppData) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let json: Data
        do {
            json = try encoder.encode(data.withoutSecrets)
        } catch {
            throw ObtainintoshError("Failed to serialize data: \(error.localizedDescription)")
        }
        try PrivateFile.writeAtomically(json, to: fileURL)
    }
}
