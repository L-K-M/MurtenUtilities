import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ObtainintoshCore

/// Reads releases from github.com's REST API: the latest release, the recent
/// list when that has nothing for this Mac, and the files on the default
/// branch for a repository that publishes fonts but no releases.
public struct GitHubClient: Sendable {
    static let apiOrigin = "https://api.github.com"
    /// Where GitHub serves repository files, outside the rate-limited API.
    static let rawOrigin = "https://raw.githubusercontent.com/"

    private let transport: HTTPTransport
    private let token: String?
    private let budget: RequestBudget?
    private let architecture: CPUArchitecture

    public init(transport: HTTPTransport, token: String?, budget: RequestBudget? = nil,
                architecture: CPUArchitecture = .current) {
        self.transport = transport
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.token = trimmed?.isEmpty == false ? trimmed : nil
        self.budget = budget
        self.architecture = architecture
    }

    /// The release to install the filtered program from, or the
    /// repository's only program when there is no filter.
    public func latestRelease(repoURL: String, filter: AssetFilter?) async throws -> Release {
        // Downloads are not authenticated, so neither are font reads.
        try await resolve(repoURL: repoURL, filter: filter)
            .release(filter: filter, architecture: architecture, transport: transport, authorization: { _ in nil })
    }

    /// The programs the release an unfiltered entry would install offers.
    public func releasePrograms(repoURL: String) async throws -> ReleasePrograms {
        try await resolve(repoURL: repoURL, filter: nil)
            .programs(architecture: architecture, transport: transport, authorization: { _ in nil })
    }

    // MARK: - Resolution

    private func resolve(repoURL: String, filter: AssetFilter?) async throws -> PublishedFiles {
        let (owner, repo) = try RepositoryURL.parseGitHub(repoURL)
        let base = "\(Self.apiOrigin)/repos/\(ForgeAPI.segment(owner))/\(ForgeAPI.segment(repo))"

        let response = try await get("\(base)/releases/latest", operation: "Failed to fetch GitHub release")
        // `releases/latest` 404s when a repository only has prereleases
        // (common for nightly builds), so the release list is the fallback.
        let latest: ForgeRelease?
        if response.status == 404 {
            latest = nil
        } else if !response.isSuccess {
            throw Self.statusFailure(response)
        } else {
            latest = try ForgeAPI.decode(ForgeRelease.self, from: response, operation: "Failed to parse GitHub release")
        }

        // The nominal latest release is usable only if it ships something this
        // Mac can install; a source-only point release would otherwise hide a
        // perfectly good build one release back.
        let stableReleasePublished = latest != nil
        if let latest, latest.hasCompatibleAsset(filter: filter, architecture: architecture) {
            return .release(latest)
        }

        let releases = try await recentReleases(base: base)
        if !stableReleasePublished && !ReleaseSelection.hasPublishedRelease(releases),
           let fonts = try await repositoryFonts(base: base, owner: owner, repo: repo) {
            return .fonts(fonts)
        }
        return .release(try ReleaseSelection.selectRecentRelease(releases, stableReleasePublished: stableReleasePublished,
                                                                 filter: filter, architecture: architecture))
    }

    private func recentReleases(base: String) async throws -> [ForgeRelease] {
        let response = try await get("\(base)/releases?per_page=\(ReleaseSelection.recentReleaseLimit)",
                                     operation: "Failed to fetch GitHub releases")
        guard response.isSuccess else { throw Self.statusFailure(response) }
        return try ForgeAPI.decode([ForgeRelease].self, from: response, operation: "Failed to parse GitHub releases")
    }

    /// The font files on the default branch, if there are any. A listing
    /// GitHub truncates offers only the fonts it lists.
    private func repositoryFonts(base: String, owner: String, repo: String) async throws -> RepositoryFonts? {
        let response = try await get("\(base)/git/trees/HEAD?recursive=1",
                                     operation: "Failed to fetch GitHub repository files")
        // An empty repository has no default branch to list (409 Conflict).
        if response.status == 404 || response.status == 409 { return nil }
        guard response.isSuccess else { throw Self.statusFailure(response) }

        let tree = try ForgeAPI.decode(RepositoryTree.self, from: response,
                                       operation: "Failed to parse GitHub repository files")
        return try RepositoryFonts.fromTree(tree.tree) { path in
            try RepositoryURL.repositoryFileURL(origin: Self.rawOrigin, prefix: [owner, repo, "HEAD"], path: path)
        }
    }

    // MARK: - Requests

    private func get(_ url: String, operation: String) async throws -> HTTPResponse {
        try await budget?.spend()
        let request = try ForgeAPI.request(url, accept: "application/vnd.github+json",
                                           authorization: token.map { "Bearer \($0)" },
                                           extraHeaders: ["X-GitHub-Api-Version": "2022-11-28"])
        let response = try await ForgeAPI.send(request, transport: transport, operation: operation)
        await budget?.record(headers: response.headers)
        return response
    }

    /// A rate-limited answer says so; anything else names the status.
    static func statusFailure(_ response: HTTPResponse) -> LookupFailure {
        let message = ForgeMessages.gitHubError(status: response.status)
        let exhausted = response.headers["x-ratelimit-remaining"] == "0"
        switch response.status {
        case 429:
            return LookupFailure(.rateLimited, message)
        case 403 where exhausted:
            return LookupFailure(.rateLimited, message + ". GitHub's request limit is used up; add a token in "
                + "Settings or try again later.")
        case 401, 403:
            return LookupFailure(.permissionDenied, message)
        default:
            return LookupFailure(.failed, message)
        }
    }
}
