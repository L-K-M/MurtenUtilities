import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ObtainintoshCore

/// Reads releases from a Forgejo (or Gitea) instance. Forgejo is
/// self-hosted, so there is no fixed host and no anonymous access to
/// assume: a private instance rejects unauthenticated reads, and the
/// credentials travel with the tracked program.
public struct ForgejoClient: Sendable {
    /// Entries of a repository's file listing asked for at a time: Forgejo's
    /// largest page.
    static let treePageSize = 1000
    /// Pages read before giving up on the rest, so a huge repository cannot
    /// cost an unbounded number of requests.
    static let maximumTreePages = 10

    private let transport: HTTPTransport
    private let credentials: ForgeCredentials
    private let architecture: CPUArchitecture

    public init(transport: HTTPTransport, credentials: ForgeCredentials, architecture: CPUArchitecture = .current) {
        self.transport = transport
        self.credentials = credentials
        self.architecture = architecture
    }

    /// The release to install the filtered program from, or the
    /// repository's only program when there is no filter.
    public func latestRelease(repoURL: String, filter: AssetFilter?) async throws -> Release {
        let auth = try downloadAuth(repoURL: repoURL)
        return try await resolve(repoURL: repoURL, filter: filter)
            .release(filter: filter, architecture: architecture, transport: transport,
                     authorization: { auth.authorizationHeader(for: $0) })
    }

    /// The programs the release an unfiltered entry would install offers.
    public func releasePrograms(repoURL: String) async throws -> ReleasePrograms {
        let auth = try downloadAuth(repoURL: repoURL)
        return try await resolve(repoURL: repoURL, filter: nil)
            .programs(architecture: architecture, transport: transport,
                      authorization: { auth.authorizationHeader(for: $0) })
    }

    /// The credentials for the asset download that follows a lookup, pinned
    /// to the instance the program is tracked from: a private repository
    /// serves its assets behind the same authentication as its API.
    public func downloadAuth(repoURL: String) throws -> DownloadAuth {
        DownloadAuth(credentials: credentials, origin: try RepositoryURL.parseForgejo(repoURL).baseURL)
    }

    // MARK: - Resolution

    private func resolve(repoURL: String, filter: AssetFilter?) async throws -> PublishedFiles {
        let repository = try RepositoryURL.parseForgejo(repoURL)
        let base = "\(repository.baseURL)/api/v1/repos/\(ForgeAPI.segment(repository.owner))/"
            + ForgeAPI.segment(repository.repo)

        // `releases/latest` returns the newest non-draft, non-prerelease
        // release and 404s when there is none, like GitHub's. A repository
        // the credentials cannot see also 404s; the release list reports it.
        let response = try await get("\(base)/releases/latest", operation: "Failed to fetch Forgejo release")
        let latest: ForgeRelease?
        if response.status == 404 {
            latest = nil
        } else if !response.isSuccess {
            throw Self.statusFailure(response.status)
        } else {
            latest = try ForgeAPI.decode(ForgeRelease.self, from: response, operation: "Failed to parse Forgejo release")
        }

        let stableReleasePublished = latest != nil
        if let latest, latest.hasCompatibleAsset(filter: filter, architecture: architecture) {
            return .release(latest)
        }

        guard let releases = try await recentReleases(base: base) else {
            // A repository with releases turned off answers 404 here, like
            // one the credentials cannot see. Its files tell the two apart.
            switch try await repositoryFiles(repository, base: base) {
            case .fonts(let fonts):
                return .fonts(fonts)
            case .withoutFonts:
                throw LookupFailure(.failed, ForgeMessages.releasesTurnedOff)
            case .notFound:
                // An empty repository, or one with its code turned off too,
                // has no files to list either; the repository shows whether
                // it can be seen.
                if try await isVisible(base: base) { throw LookupFailure(.failed, ForgeMessages.releasesTurnedOff) }
                throw LookupFailure(.permissionDenied, ForgeMessages.repositoryNotFound)
            }
        }

        if !stableReleasePublished && !ReleaseSelection.hasPublishedRelease(releases),
           case .fonts(let fonts) = try await repositoryFiles(repository, base: base) {
            return .fonts(fonts)
        }
        return .release(try ReleaseSelection.selectRecentRelease(releases, stableReleasePublished: stableReleasePublished,
                                                                 filter: filter, architecture: architecture))
    }

    /// The recent releases, or nil when the release list is not found.
    private func recentReleases(base: String) async throws -> [ForgeRelease]? {
        let response = try await get("\(base)/releases?limit=\(ReleaseSelection.recentReleaseLimit)",
                                     operation: "Failed to fetch Forgejo releases")
        if response.status == 404 { return nil }
        guard response.isSuccess else { throw Self.statusFailure(response.status) }
        return try ForgeAPI.decode([ForgeRelease].self, from: response, operation: "Failed to parse Forgejo releases")
    }

    /// Whether the credentials can see the repository at all.
    private func isVisible(base: String) async throws -> Bool {
        let response = try await get(base, operation: "Failed to fetch the Forgejo repository")
        if response.status == 404 { return false }
        guard response.isSuccess else { throw Self.statusFailure(response.status) }
        return true
    }

    /// What listing a repository's files finds.
    private enum RepositoryFiles {
        /// Not found: the repository is not visible, or has no files.
        case notFound
        /// Visible, but without font files.
        case withoutFonts
        case fonts(RepositoryFonts)
    }

    /// The font files on the default branch. Forgejo pages the listing;
    /// `total_count` says when it is complete.
    private func repositoryFiles(_ repository: RepositoryURL.ForgejoRepository,
                                 base: String) async throws -> RepositoryFiles {
        let treeURL = "\(base)/git/trees/HEAD?recursive=true&per_page=\(Self.treePageSize)"
        var entries: [RepositoryTree.Entry] = []
        for page in 1...Self.maximumTreePages {
            let response = try await get("\(treeURL)&page=\(page)", operation: "Failed to fetch Forgejo repository files")
            if response.status == 404 { return .notFound }
            guard response.isSuccess else { throw Self.statusFailure(response.status) }

            let tree = try ForgeAPI.decode(RepositoryTree.self, from: response,
                                           operation: "Failed to parse Forgejo repository files")
            entries += tree.tree
            if tree.tree.isEmpty || entries.count >= (tree.totalCount ?? 0) { break }
        }

        let fonts = try RepositoryFonts.fromTree(entries) { path in
            try RepositoryURL.repositoryFileURL(origin: repository.baseURL + "/",
                                                prefix: ["api", "v1", "repos", repository.owner, repository.repo, "raw"],
                                                path: path)
        }
        return fonts.map(RepositoryFiles.fonts) ?? .withoutFonts
    }

    // MARK: - Requests

    /// API requests carry the credentials as typed: the URL is built from
    /// the instance the user named. Over `http://` the key travels in clear
    /// text; the pane warns about that where it is entered.
    private func get(_ url: String, operation: String) async throws -> HTTPResponse {
        let request = try ForgeAPI.request(url, accept: "application/json",
                                           authorization: credentials.authorizationHeader)
        return try await ForgeAPI.send(request, transport: transport, operation: operation)
    }

    /// The usual cause of a refusal is a credential problem.
    static func statusFailure(_ status: Int) -> LookupFailure {
        let kind: LookupFailure.Kind = (status == 401 || status == 403) ? .permissionDenied
            : (status == 429 ? .rateLimited : .failed)
        return LookupFailure(kind, ForgeMessages.forgejoError(status: status))
    }
}
