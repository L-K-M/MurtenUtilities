import Foundation
import RunningManCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// One look at the installed runners for the suite's background check.
public struct RunnerStateReading: Sendable {
    public var snapshots: [RunnerSnapshot]
    /// Candidate runner folders left unread because macOS protects them.
    public var skippedDirectories: [URL]
    /// Discovery read every unskipped candidate without unreadable runner settings or
    /// truncated folder listings. Skipped folders are recorded separately.
    public var discoveryComplete: Bool

    public init(snapshots: [RunnerSnapshot], skippedDirectories: [URL] = [], discoveryComplete: Bool = false) {
        self.snapshots = snapshots
        self.skippedDirectories = skippedDirectories
        self.discoveryComplete = discoveryComplete
    }
}

/// The observation-only interface the background check gets: it can look at runners,
/// never start, stop or change them.
public protocol RunnerStateProbing: Sendable {
    func read(additionalDirectories: [URL]) async -> RunnerStateReading
}

/// Reads runner health the way the pane does, minus everything a background check may
/// not do: discovery skips privacy-protected folders, and launchd and process state is
/// read without server activity, so the check makes no network request and never reads
/// a Forgejo token from the Keychain. The service controller it wraps stays private, so
/// none of its start, stop or delete operations are reachable from here.
public struct RunnerHealthProbe: RunnerStateProbing {
    private let discovery: RunnerDiscovery
    private let controller: RunnerServiceController

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(homeDirectory: homeDirectory, systemDaemonsDirectory: RunnerDiscovery.systemDaemonsDirectory,
                  executor: SystemProcessExecutor(), userID: getuid())
    }

    init(homeDirectory: URL, systemDaemonsDirectory: URL?, executor: any ProcessExecuting, userID: UInt32) {
        discovery = RunnerDiscovery(homeDirectory: homeDirectory, systemDaemonsDirectory: systemDaemonsDirectory,
                                    excludedFolders: Self.privacyProtectedFolders(homeDirectory: homeDirectory))
        controller = RunnerServiceController(homeDirectory: homeDirectory, executor: executor, userID: userID,
                                             forgejoAPI: NoRemoteAccess())
    }

    /// Reading inside these can make macOS ask for access (Files and Folders, iCloud
    /// Drive, other apps' data, removable and network volumes).
    public static func privacyProtectedFolders(homeDirectory: URL) -> [URL] {
        ["Desktop", "Documents", "Downloads", "Library/Mobile Documents", "Library/CloudStorage",
         "Library/Containers", "Library/Group Containers"].map { homeDirectory.appendingPathComponent($0, isDirectory: true) }
            + [URL(fileURLWithPath: "/Volumes", isDirectory: true)]
    }

    public func read(additionalDirectories: [URL]) async -> RunnerStateReading {
        let found = await discovery.discover(additionalDirectories: additionalDirectories)
        let snapshots = await controller.snapshots(for: found.runners, allowRemoteActivity: false)
        return RunnerStateReading(snapshots: snapshots, skippedDirectories: found.skippedDirectories,
                                  discoveryComplete: found.warnings.isEmpty)
    }
}

/// Stands in for the Forgejo API so that even an unexpected call cannot reach the
/// network or the Keychain from a background check.
private struct NoRemoteAccess: ForgejoAPIRequesting {
    func request(path: String, serverURL: URL, method: String, body: Data?) async throws -> Data {
        throw RunnerServiceError("The background check does not contact Forgejo servers.")
    }
}
