import XCTest
@testable import ObtainintoshCore

final class RepositoryURLTests: XCTestCase {
    private func gitHub(_ url: String) throws -> [String] {
        let parsed = try RepositoryURL.parseGitHub(url)
        return [parsed.owner, parsed.repo]
    }

    func testParseGitHubURLBasic() throws {
        XCTAssertEqual(try gitHub("https://github.com/owner/repo"), ["owner", "repo"])
        XCTAssertEqual(try gitHub("https://github.com/owner/repo/"), ["owner", "repo"])
        XCTAssertEqual(try gitHub("github.com/owner/repo"), ["owner", "repo"])
    }

    func testNormalizeRepositoryURL() {
        for url in [
            "https://github.com/Owner/Repo", "https://GitHub.com/owner/repo/", "https://github.com/owner/repo.git",
            "https://github.com/owner/repo.git/", "https://github.com/owner/repo.GIT", "http://github.com/owner/repo",
            "https://www.github.com/owner/repo", "http://WWW.github.com/owner/repo.Git/",
            "https://github.com/owner/repo?tab=readme", "https://github.com/owner/repo/#readme",
        ] {
            XCTAssertEqual(RepositoryURL.normalize(url), "https://github.com/owner/repo", url)
        }
    }

    func testParseGitHubURLExtraSegments() throws {
        XCTAssertEqual(try gitHub("https://github.com/owner/repo/releases/latest"), ["owner", "repo"])
        XCTAssertEqual(try gitHub("https://github.com/owner/repo/tree/main/src"), ["owner", "repo"])
    }

    func testParseGitHubURLGitSuffixAndQuery() throws {
        XCTAssertEqual(try gitHub("https://github.com/owner/repo.git"), ["owner", "repo"])
        XCTAssertEqual(try gitHub("https://github.com/owner/repo?tab=readme"), ["owner", "repo"])
        XCTAssertEqual(try gitHub("https://www.github.com/owner/repo#readme"), ["owner", "repo"])
    }

    func testParseGitHubURLInvalid() {
        for url in ["https://github.com/owner", "https://github.com/", "https://example.com/owner/repo", "not a url"] {
            XCTAssertThrowsError(try RepositoryURL.parseGitHub(url), url)
        }
    }

    func testParseForgejoURLAcceptsAnyHost() throws {
        let cases: [(String, [String])] = [
            ("https://codeberg.org/owner/repo", ["https://codeberg.org", "owner", "repo"]),
            ("https://git.example.internal/owner/repo/", ["https://git.example.internal", "owner", "repo"]),
            // Scheme-less input is assumed to be https, like the GitHub parser.
            ("git.example.internal/owner/repo", ["https://git.example.internal", "owner", "repo"]),
            // A plain-http instance on a non-standard port stays intact.
            ("http://192.168.1.10:3000/owner/repo", ["http://192.168.1.10:3000", "owner", "repo"]),
            // Case is normalised on the host only.
            ("https://Git.Example.INTERNAL/Owner/Repo", ["https://git.example.internal", "Owner", "Repo"]),
            ("https://git.example.internal/owner/repo.git", ["https://git.example.internal", "owner", "repo"]),
            ("https://git.example.internal/owner/repo?tab=releases", ["https://git.example.internal", "owner", "repo"]),
            ("https://git.example.internal/owner/repo#readme", ["https://git.example.internal", "owner", "repo"]),
            // Anything past the repository is ignored.
            ("https://git.example.internal/owner/repo/releases/tag/v1.0.0",
             ["https://git.example.internal", "owner", "repo"]),
            ("https://git.example.internal/owner/repo/src/branch/main", ["https://git.example.internal", "owner", "repo"]),
        ]
        for (url, expected) in cases {
            let parsed = try RepositoryURL.parseForgejo(url)
            XCTAssertEqual([parsed.baseURL, parsed.owner, parsed.repo], expected, url)
        }
    }

    func testParseForgejoURLDropsUserinfo() throws {
        // Credentials belong in the dialog's fields and must never end up in
        // the instance origin.
        let parsed = try RepositoryURL.parseForgejo("https://user:secret@git.example.internal/owner/repo")
        XCTAssertEqual(parsed.baseURL, "https://git.example.internal")
        XCTAssertEqual([parsed.owner, parsed.repo], ["owner", "repo"])
    }

    func testParseForgejoURLInvalid() {
        for url in ["https://git.example.internal/owner", "https://git.example.internal/", "https://git.example.internal",
                    "not a url", "ftp://git.example.internal/owner/repo", "javascript://x/owner/repo"] {
            XCTAssertThrowsError(try RepositoryURL.parseForgejo(url), url)
        }
    }

    func testDetectSourceType() {
        let cases: [(String, SourceType?)] = [
            ("https://github.com/owner/repo", .github),
            ("https://gitlab.com/owner/repo", .gitlab),
            ("https://codeberg.org/owner/repo", .forgejo),
            ("https://Codeberg.org/owner/repo", .forgejo),
            ("https://forgejo.example.org/owner/repo", .forgejo),
            ("https://gitea.example.org/owner/repo", .forgejo),
            // A private instance on an unremarkable host cannot be guessed.
            ("https://git.example.internal/owner/repo", nil),
            ("https://example.com/downloads", nil),
        ]
        for (url, expected) in cases {
            XCTAssertEqual(RepositoryURL.detectSourceType(url), expected, url)
        }
    }

    func testPlaintextHTTPIsRecognised() {
        for url in ["http://192.168.1.10:3000/owner/repo", "HTTP://git.example.internal/owner/repo",
                    "  http://git.example.internal/owner/repo"] {
            XCTAssertTrue(RepositoryURL.isPlaintextHTTP(url), url)
        }
        for url in ["https://git.example.internal/owner/repo", "HTTPS://git.example.internal/owner/repo",
                    "https://http.example.internal/owner/repo", "http", "",
                    // Byte 7 falls inside the two-byte "é".
                    "http:/éxample.internal/owner/repo"] {
            XCTAssertFalse(RepositoryURL.isPlaintextHTTP(url), url)
        }
    }

    func testSameOrigin() {
        XCTAssertTrue(RepositoryURL.sameOrigin("https://git.example.internal/a/b", "https://git.example.internal"))
        // A stored scheme-less URL is read as https.
        XCTAssertTrue(RepositoryURL.sameOrigin("https://codeberg.org/owner/repo", "codeberg.org"))
        // The default port is implied.
        XCTAssertTrue(RepositoryURL.sameOrigin("https://git.example.internal:443/a/b", "https://git.example.internal"))
        XCTAssertFalse(RepositoryURL.sameOrigin("https://git.example.internal:3000/a/b", "https://git.example.internal"))
        XCTAssertFalse(RepositoryURL.sameOrigin("https://evil.example.com/a/b", "https://git.example.internal"))
        // A host suffix is not the same origin.
        XCTAssertFalse(RepositoryURL.sameOrigin("https://git.example.internal.evil.com/a/b",
                                                "https://git.example.internal"))
        XCTAssertFalse(RepositoryURL.sameOrigin("", "https://git.example.internal"))
    }

    func testRepositoryFilePathsCannotLeaveTheRepository() throws {
        let url = try RepositoryURL.repositoryFileURL(origin: "https://raw.githubusercontent.com/",
                                                      prefix: ["owner", "repo", "HEAD"],
                                                      path: "../../other/repo/HEAD/Font.ttf")
        // "." and ".." segments are dropped rather than encoded.
        XCTAssertEqual(url, "https://raw.githubusercontent.com/owner/repo/HEAD/other/repo/HEAD/Font.ttf")
    }

    func testRepositoryFileURLsEncodeEachSegment() throws {
        XCTAssertEqual(
            try RepositoryURL.repositoryFileURL(origin: "https://raw.githubusercontent.com/",
                                                prefix: ["szabadkai", "c64-keyboard-font", "HEAD"],
                                                path: "fonts/C64 Keyboard#1.ttf"),
            "https://raw.githubusercontent.com/szabadkai/c64-keyboard-font/HEAD/fonts/C64%20Keyboard%231.ttf")
        XCTAssertEqual(
            try RepositoryURL.repositoryFileURL(origin: "http://127.0.0.1:3000/",
                                                prefix: ["api", "v1", "repos", "owner", "repo", "raw"], path: "A.otf"),
            "http://127.0.0.1:3000/api/v1/repos/owner/repo/raw/A.otf")
    }
}
