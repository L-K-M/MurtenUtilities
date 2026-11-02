import Foundation
import ObtainintoshCore

/// The credentials a lookup may send: the GitHub token for GitHub, the
/// program's own Forgejo credentials for Forgejo.
public struct LookupCredentials: Sendable {
    public var gitHubToken: String?
    public var forge: ForgeCredentials

    public init(gitHubToken: String? = nil, forge: ForgeCredentials = ForgeCredentials()) {
        self.gitHubToken = gitHubToken
        self.forge = forge
    }
}

/// Finds a tracked program's latest release on its forge. Only reads: the
/// pane and the background check share it.
public protocol ReleaseLooking: Sendable {
    func latestRelease(of app: TrackedApp, credentials: LookupCredentials, budget: RequestBudget?) async throws -> Release
    func releasePrograms(for input: SourceInput, credentials: LookupCredentials) async throws -> ReleasePrograms
    /// What the asset download must authenticate with, nil when nothing.
    func downloadAuth(for app: TrackedApp, credentials: LookupCredentials) throws -> DownloadAuth?
}

/// Dispatches to the forge's client.
public struct ReleaseLookup: ReleaseLooking {
    static let gitLabUnsupported = "GitLab support not yet implemented"

    private let transport: HTTPTransport

    public init(transport: HTTPTransport) {
        self.transport = transport
    }

    public func latestRelease(of app: TrackedApp, credentials: LookupCredentials,
                              budget: RequestBudget?) async throws -> Release {
        // A filter that does not parse was edited into the file by hand; the
        // check reports it rather than quietly tracking another program.
        let filter: AssetFilter?
        do {
            filter = try AssetFilter.parse(app.assetFilter ?? "")
        } catch {
            throw LookupFailure(.failed, "The stored program filter is invalid: \(error.localizedDescription)")
        }

        switch app.sourceType {
        case .github:
            return try await GitHubClient(transport: transport, token: credentials.gitHubToken, budget: budget)
                .latestRelease(repoURL: app.sourceURL, filter: filter)
        case .forgejo:
            return try await ForgejoClient(transport: transport, credentials: credentials.forge)
                .latestRelease(repoURL: app.sourceURL, filter: filter)
        case .gitlab:
            throw LookupFailure(.unsupported, Self.gitLabUnsupported)
        }
    }

    public func releasePrograms(for input: SourceInput, credentials: LookupCredentials) async throws -> ReleasePrograms {
        switch try input.resolvedSourceType() {
        case .github:
            return try await GitHubClient(transport: transport, token: credentials.gitHubToken)
                .releasePrograms(repoURL: input.url)
        case .forgejo:
            return try await ForgejoClient(transport: transport, credentials: credentials.forge)
                .releasePrograms(repoURL: input.url)
        case .gitlab:
            throw LookupFailure(.unsupported, Self.gitLabUnsupported)
        }
    }

    public func downloadAuth(for app: TrackedApp, credentials: LookupCredentials) throws -> DownloadAuth? {
        switch app.sourceType {
        case .forgejo:
            return try ForgejoClient(transport: transport, credentials: credentials.forge)
                .downloadAuth(repoURL: app.sourceURL)
        case .github, .gitlab:
            return nil
        }
    }
}
