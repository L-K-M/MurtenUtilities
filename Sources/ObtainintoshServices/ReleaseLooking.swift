import Foundation
import ObtainintoshCore

/// Finds a tracked program's latest release on its forge. Only reads: the
/// pane and the background check share it.
public protocol ReleaseLooking: Sendable {
    func latestRelease(of app: TrackedApp, credentials: LookupCredentials, budget: RequestBudget?) async throws -> Release
    func releasePrograms(for input: SourceInput, credentials: LookupCredentials) async throws -> ReleasePrograms
    /// What the asset download must authenticate with, nil when nothing.
    func downloadAuth(for app: TrackedApp, credentials: LookupCredentials) throws -> DownloadAuth?
}
