import Foundation
import ObtainintoshCore

/// Everything the background check may do, and nothing more: read the
/// saved list, read installed versions, and ask forges for releases. No
/// method writes, needs privilege or can prompt.
public protocol UpdateObserving: Sendable {
    /// The tracked list as last saved, read without writing; nil when there
    /// is none yet.
    func trackedList() throws -> TrackedAppData?
    /// Each program's installed copy, from the file system.
    func installedVersions(of apps: [TrackedApp]) async -> [InstalledVersion?]
    /// How many GitHub API requests one poll may spend.
    func gitHubAllowance() async -> Int
    /// The program's latest release, sent with only the credentials this
    /// session already holds in memory.
    func latestRelease(of app: TrackedApp, budget: RequestBudget) async throws -> Release
}
