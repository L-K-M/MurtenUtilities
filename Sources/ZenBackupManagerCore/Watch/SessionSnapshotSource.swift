import Foundation

/// What the background check may ask about Zen's session snapshots: which
/// profiles exist and when each one last saved. It reads Zen's profile list
/// and file dates only. It never opens a session file, never writes, and
/// needs nothing beyond the user's own access to
/// ~/Library/Application Support/zen, which is not a privacy-protected folder.
public protocol SessionSnapshotSource: Sendable {
    /// The profiles in Zen's profiles.ini; empty when Zen has none.
    func profiles() throws -> [ZenProfile]

    /// When Zen last wrote a session snapshot for the profile, nil when it
    /// has none. Safety copies are this app's, not Zen's, and do not count.
    func newestSnapshot(in profile: ZenProfile) throws -> Date?
}

/// Dates the snapshots from file metadata: the same files the timeline
/// lists, minus safety copies.
public struct SessionSnapshotReader: SessionSnapshotSource {
    private let zenRoot: URL

    public init(zenRoot: URL) {
        self.zenRoot = zenRoot
    }

    public func profiles() throws -> [ZenProfile] {
        try ProfileDiscovery.discover(root: zenRoot)
    }

    public func newestSnapshot(in profile: ZenProfile) throws -> Date? {
        // A backup Zen rotated away between listing and dating is skipped:
        // it is no longer a snapshot.
        try BackupCatalog.snapshotFiles(in: profile)
            .compactMap { file, _ in try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .max()
    }
}
