import Foundation

/// The tracked list's rules as a pure value: dedupe, id assignment, edits,
/// tombstones and the narrow write a finished check may make. The services'
/// store owns one, persists every proposed state and adopts it only once it
/// is on disk.
public struct TrackedAppList: Equatable, Sendable {
    public private(set) var data: TrackedAppData

    public init(data: TrackedAppData = TrackedAppData()) {
        self.data = data
    }

    public var apps: [TrackedApp] { data.apps }

    public func app(id: String) -> TrackedApp? {
        data.apps.first { $0.id == id }
    }

    // MARK: - Adding

    /// What a batch add did with each program, in the order given.
    public struct BatchAddition: Equatable, Sendable {
        public var added: [TrackedApp] = []
        /// Programs whose repository and program were tracked already.
        public var duplicates: [TrackedApp] = []
    }

    /// Adds programs, skipping any whose repository and program are tracked
    /// already, by an existing entry or an earlier one of the batch. Ids are
    /// assigned to entries without one or whose id is taken: every path
    /// that resolves a program by id assumes ids are unique.
    public mutating func add(_ apps: [TrackedApp],
                             makeID: () -> String = { UUID().uuidString.lowercased() }) -> BatchAddition {
        var tracked = Set(data.apps.map(Self.trackingKey))
        var ids = Set(data.apps.map(\.id))
        var addition = BatchAddition()
        for var app in apps {
            guard tracked.insert(Self.trackingKey(app)).inserted else {
                addition.duplicates.append(app)
                continue
            }
            if app.id.isEmpty || ids.contains(app.id) {
                repeat { app.id = makeID() } while ids.contains(app.id)
            }
            ids.insert(app.id)
            data.removedAppIDs.removeAll { $0 == app.id }
            data.apps.append(app)
            addition.added.append(app)
        }
        return addition
    }

    /// Adds one program, refusing a repository and program tracked already.
    public mutating func addOne(_ app: TrackedApp,
                                makeID: () -> String = { UUID().uuidString.lowercased() }) throws -> TrackedApp {
        guard let added = add([app], makeID: makeID).added.first else { throw Self.alreadyTracked(app) }
        return added
    }

    // MARK: - Editing

    /// Replaces a record. An edit must not turn an entry into a copy of
    /// another; only a changed identity is checked, so entries that already
    /// collide (edits were not checked before) stay editable.
    public mutating func update(_ updated: TrackedApp) throws {
        guard let index = data.apps.firstIndex(where: { $0.id == updated.id }) else {
            throw ObtainintoshError("App not found: \(updated.id)")
        }
        let key = Self.trackingKey(updated)
        let identityChanged = Self.trackingKey(data.apps[index]) != key
        if identityChanged && data.apps.contains(where: { $0.id != updated.id && Self.trackingKey($0) == key }) {
            throw Self.alreadyTracked(updated)
        }
        data.apps[index] = updated
    }

    /// Removes a record and remembers its id, so the background check can
    /// report the program as no longer tracked.
    public mutating func remove(id: String) {
        guard data.apps.contains(where: { $0.id == id }) else { return }
        data.apps.removeAll { $0.id == id }
        data.removedAppIDs.removeAll { $0 == id }
        data.removedAppIDs.append(id)
        if data.removedAppIDs.count > TrackedAppData.removedIDLimit {
            data.removedAppIDs.removeFirst(data.removedAppIDs.count - TrackedAppData.removedIDLimit)
        }
    }

    /// Clears the `downloaded` record of the named programs; returns how many
    /// changed. The cache is temporary, so records go stale on their own.
    @discardableResult
    public mutating func forgetDownloads(_ ids: [String]) -> Int {
        var cleared = 0
        for index in data.apps.indices where ids.contains(data.apps[index].id) && data.apps[index].downloaded != nil {
            data.apps[index].downloaded = nil
            cleared += 1
        }
        return cleared
    }

    // MARK: - Check results

    /// Applies the outcome of a check that ran against `snapshot`, writing
    /// only the fields a check owns and only if the record still matches
    /// what was checked. A batch check runs against a snapshot taken before
    /// the network work, so by the time a result lands the user may have
    /// removed or edited the program.
    public mutating func applyCheckResult(snapshot: TrackedApp, update: CheckOwnedUpdate) -> PendingResultApplication {
        guard let index = data.apps.firstIndex(where: { $0.id == snapshot.id }) else { return .appRemoved }
        let current = data.apps[index]
        guard current.name == snapshot.name, Self.sameSourceIdentity(current, snapshot),
              Self.sameCheckMetadata(current, snapshot) else { return .dependenciesChanged }

        data.apps[index].currentVersion = update.currentVersion
        data.apps[index].installPath = update.installPath
        // A failed check must not touch latestVersion or lastChecked: the
        // previously known version stays, flagged as stale by the attempt.
        if update.attempt.state == .succeeded {
            data.apps[index].latestVersion = update.latestVersion
            data.apps[index].lastChecked = update.attempt.attemptedAt
        }
        data.apps[index].lastCheckAttempt = update.attempt
        return .applied
    }

    // MARK: - Identity

    /// What makes two entries track the same thing: the repository, and the
    /// program of its releases when the entry names one.
    public struct TrackingKey: Hashable, Sendable {
        let repository: String
        let program: String?
    }

    public static func trackingKey(_ app: TrackedApp) -> TrackingKey {
        TrackingKey(repository: RepositoryURL.normalize(app.sourceURL), program: canonicalFilter(app.assetFilter))
    }

    /// The stored filter in canonical form. Every write path stores it that
    /// way; this covers a hand-edited file, where `Seance` and `seance` must
    /// still be one program and an empty filter none. A filter that does not
    /// parse is compared as written; its next check reports it.
    private static func canonicalFilter(_ stored: String?) -> String? {
        guard let stored else { return nil }
        do {
            return try AssetFilter.canonicalize(stored)
        } catch {
            return stored
        }
    }

    public static func alreadyTracked(_ app: TrackedApp) -> ObtainintoshError {
        if let program = app.assetFilter {
            return ObtainintoshError("\"\(program)\" from this repository is already being tracked")
        }
        return ObtainintoshError("This repository is already being tracked")
    }

    private static func sameSourceIdentity(_ left: TrackedApp, _ right: TrackedApp) -> Bool {
        left.sourceType == right.sourceType && trackingKey(left) == trackingKey(right)
    }

    /// Whether the check-owned fields are as the snapshot left them. If they
    /// moved, another check landed already and this result is the older one.
    private static func sameCheckMetadata(_ left: TrackedApp, _ right: TrackedApp) -> Bool {
        left.latestVersion == right.latestVersion && left.lastChecked == right.lastChecked
            && left.lastCheckAttempt == right.lastCheckAttempt
    }
}
