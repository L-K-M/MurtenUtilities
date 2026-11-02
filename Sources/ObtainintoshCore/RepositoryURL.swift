import Foundation

/// Parsing and comparing the repository URLs users type, and building the
/// URLs the forge clients request.
public enum RepositoryURL {
    /// A repository's location on a Forgejo instance.
    public struct ForgejoRepository: Equatable, Sendable {
        /// `scheme://host[:port]`, host lowercased.
        public let baseURL: String
        public let owner: String
        public let repo: String
    }

    /// Canonical form for "is this the same repository?" comparisons:
    /// lowercased first (so `.GIT` trims like `.git`), query and fragment
    /// dropped, trailing slash and `.git` stripped, `http://` folded into
    /// `https://` and a `www.` host prefix dropped.
    public static func normalize(_ url: String) -> String {
        let base = url.asciiLowercased().beforeQueryOrFragment()
        let trimmed = base.trimmingSuffixRepeatedly("/").trimmingSuffixRepeatedly(".git").trimmingSuffixRepeatedly("/")
        let rest: Substring
        if trimmed.hasPrefix("https://") {
            rest = trimmed.dropFirst("https://".count)
        } else if trimmed.hasPrefix("http://") {
            rest = trimmed.dropFirst("http://".count)
        } else {
            return trimmed
        }
        return "https://" + (rest.hasPrefix("www.") ? rest.dropFirst("www.".count) : rest)
    }

    /// `owner` and `repo` of a github.com URL. Anything past them
    /// (`/releases`, `/tree/main`), a query, a fragment and a trailing
    /// `.git` are ignored.
    public static func parseGitHub(_ url: String) throws -> (owner: String, repo: String) {
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutScheme = url.components(separatedBy: "://").last ?? url
        var parts = withoutScheme.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            .makeIterator()

        let invalid = ObtainintoshError("Invalid GitHub URL: expected github.com/<owner>/<repo>")
        let host = (parts.next() ?? "").asciiLowercased()
        guard host == "github.com" || host == "www.github.com" else { throw invalid }

        guard let ownerPart = parts.next() else {
            throw ObtainintoshError("GitHub URL is missing the repository owner")
        }
        guard let repoPart = parts.next() else {
            throw ObtainintoshError("GitHub URL is missing the repository name")
        }
        let owner = ownerPart.beforeQueryOrFragment()
        let repo = repoPart.beforeQueryOrFragment().trimmingSuffixRepeatedly(".git")
        guard !owner.isEmpty, !repo.isEmpty else { throw invalid }
        return (owner, repo)
    }

    /// Splits a Forgejo repository URL into the instance base URL and the
    /// owner/repo pair. The host is whatever the user self-hosts, so only the
    /// `<owner>/<repo>` shape of the path is fixed; anything past it is
    /// ignored. A URL without a scheme is https. An instance under a URL
    /// path prefix is not supported.
    public static func parseForgejo(_ url: String) throws -> ForgejoRepository {
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme: String
        let rest: String
        if let separator = url.range(of: "://") {
            scheme = String(url[..<separator.lowerBound]).asciiLowercased()
            rest = String(url[separator.upperBound...])
        } else {
            scheme = "https"
            rest = url
        }
        guard scheme == "https" || scheme == "http" else {
            throw ObtainintoshError("Unsupported URL scheme for a Forgejo instance: \(scheme)")
        }

        var parts = rest.split(separator: "/", omittingEmptySubsequences: true).map(String.init).makeIterator()
        // Hosts are case-insensitive; owner and repo keep the case typed.
        let authority = (parts.next() ?? "").beforeQueryOrFragment().asciiLowercased()
        // Drop any `user:password@` prefix rather than folding it into the host.
        let host = authority.range(of: "@", options: .backwards).map { String(authority[$0.upperBound...]) }
            ?? authority

        guard let ownerPart = parts.next() else {
            throw ObtainintoshError("Forgejo URL is missing the repository owner")
        }
        guard let repoPart = parts.next() else {
            throw ObtainintoshError("Forgejo URL is missing the repository name")
        }
        let owner = ownerPart.beforeQueryOrFragment()
        let repo = repoPart.beforeQueryOrFragment().trimmingSuffixRepeatedly(".git")

        let invalid = ObtainintoshError("Invalid Forgejo URL: expected <host>/<owner>/<repo>")
        guard !host.isEmpty, host.contains(where: \.isASCIIAlphanumeric) else { throw invalid }
        guard !owner.isEmpty, !repo.isEmpty else { throw invalid }
        return ForgejoRepository(baseURL: "\(scheme)://\(host)", owner: owner, repo: repo)
    }

    /// Best-effort guess at the forge a URL belongs to, used when the user
    /// has not picked one. Forgejo has no canonical host, so only the public
    /// flagship and hosts that name the software are recognised.
    public static func detectSourceType(_ url: String) -> SourceType? {
        if url.contains("github.com") { return .github }
        if url.contains("gitlab.com") || url.contains("gitlab") { return .gitlab }
        if let host = host(of: url), looksLikeForgejoHost(host) { return .forgejo }
        return nil
    }

    /// The lowercased host of a URL, without userinfo and port. A bracketed
    /// IPv6 literal comes back truncated, which does not matter: IP literals
    /// never name forge software, so such a URL falls through to "not
    /// detected".
    static func host(of url: String) -> String? {
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = url.range(of: "://").map { String(url[$0.upperBound...]) } ?? url
        let authority = String(rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" })
        let hostAndPort = authority.range(of: "@", options: .backwards).map { String(authority[$0.upperBound...]) }
            ?? authority
        let host = String(hostAndPort.prefix { $0 != ":" })
        return host.isEmpty ? nil : host.asciiLowercased()
    }

    /// Codeberg is the public Forgejo instance, and self-hosters name the
    /// host after the software (`forgejo.example.org`, `git.gitea.io`).
    /// Gitea counts: Forgejo's API is a superset of the one used here.
    static func looksLikeForgejoHost(_ host: String) -> Bool {
        host == "codeberg.org" || host.hasSuffix(".codeberg.org")
            || host.split(separator: ".", omittingEmptySubsequences: false)
                .contains { $0.contains("forgejo") || $0.contains("gitea") }
    }

    /// Whether two URLs address the same origin (scheme, host, port),
    /// treating a missing scheme as https so a stored `codeberg.org/o/r`
    /// still matches its own asset URLs.
    public static func sameOrigin(_ a: String, _ b: String) -> Bool {
        guard let left = origin(of: a), let right = origin(of: b) else { return false }
        return left == right
    }

    private struct Origin: Equatable {
        let scheme: String
        let host: String
        let port: Int?
    }

    private static func origin(of url: String) -> Origin? {
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let absolute = url.contains("://") ? url : "https://" + url
        guard let components = URLComponents(string: absolute), let scheme = components.scheme?.asciiLowercased(),
              let host = components.host, !host.isEmpty else { return nil }
        let defaultPort: Int?
        switch scheme {
        case "https": defaultPort = 443
        case "http": defaultPort = 80
        default: defaultPort = nil
        }
        return Origin(scheme: scheme, host: host.asciiLowercased(), port: components.port ?? defaultPort)
    }

    /// Whether credentials sent to `url` would travel unencrypted. Compares
    /// bytes, so a URL whose seventh byte falls inside a multi-byte
    /// character is simply not plain HTTP.
    public static func isPlaintextHTTP(_ url: String) -> Bool {
        let bytes = Array(url.drop(while: \.isWhitespace).utf8.prefix(7))
        let expected = Array("http://".utf8)
        guard bytes.count == expected.count else { return false }
        return zip(bytes, expected).allSatisfy { byte, wanted in
            let folded = (byte >= 0x41 && byte <= 0x5A) ? byte + 32 : byte
            return folded == wanted
        }
    }

    /// The URL of a repository file: `origin`, then `prefix`, then the file's
    /// path, each segment percent-encoded (`My Font.ttf` → `My%20Font.ttf`).
    /// `.` and `..` segments are dropped, so a path cannot leave the
    /// repository.
    public static func repositoryFileURL(origin: String, prefix: [String], path: String) throws -> String {
        guard let components = URLComponents(string: origin), components.scheme != nil,
              let host = components.host, !host.isEmpty else {
            throw ObtainintoshError("Invalid repository URL")
        }
        var base = origin
        if base.hasSuffix("/") { base.removeLast() }

        let segments = (prefix + path.split(separator: "/", omittingEmptySubsequences: false).map(String.init))
            .filter { $0 != "." && $0 != ".." }
        return base + "/" + segments.map(percentEncodePathSegment).joined(separator: "/")
    }

    /// Bytes encoded in a path segment, as the WHATWG URL standard's path
    /// segment set plus `\`: controls, space, `"#<>?`{}/%\` and non-ASCII.
    private static let segmentReserved = Set("\"#<>?`{}/%\\ ".utf8)

    private static func percentEncodePathSegment(_ segment: String) -> String {
        var encoded = ""
        for byte in segment.utf8 {
            if byte < 0x20 || byte >= 0x7F || segmentReserved.contains(byte) {
                encoded += String(format: "%%%02X", byte)
            } else {
                encoded.unicodeScalars.append(Unicode.Scalar(byte))
            }
        }
        return encoded
    }
}
