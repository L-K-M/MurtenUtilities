import XCTest
import ObtainintoshCore
@testable import ObtainintoshServices

final class GitHubClientTests: XCTestCase {
    private let repo = "https://github.com/owner/tool"

    private func releaseJSON(_ tag: String, prerelease: Bool = false, _ assets: [String]) -> String {
        let list = assets.map {
            #"{"name": "\#($0)", "size": 2048, "browser_download_url": "https://github.com/owner/tool/releases/download/\#(tag)/\#($0)"}"#
        }
        return #"{"tag_name": "\#(tag)", "draft": false, "prerelease": \#(prerelease), "assets": [\#(list.joined(separator: ","))]}"#
    }

    func testReadsTheLatestReleaseWithTheToken() async throws {
        let github = FakeTransport([.json(200, releaseJSON("v2.1.0", ["tool-macos-universal.dmg"]))])

        let release = try await GitHubClient(transport: github, token: " ghp_token ").latestRelease(repoURL: repo, filter: nil)

        XCTAssertEqual(release.version, "2.1.0")
        XCTAssertEqual(release.fileName, "tool-macos-universal.dmg")
        XCTAssertEqual(github.requests.map(\.url.absoluteString), ["https://api.github.com/repos/owner/tool/releases/latest"])
        XCTAssertEqual(github.requests[0].authorization, "Bearer ghp_token")
    }

    func testABlankTokenSendsNothing() async throws {
        let github = FakeTransport([.json(200, releaseJSON("v1.0.0", ["tool.dmg"]))])
        _ = try await GitHubClient(transport: github, token: "  ").latestRelease(repoURL: repo, filter: nil)
        XCTAssertNil(github.requests[0].authorization)
    }

    func testFallsBackToTheRecentListWhenLatestHasNothingForThisMac() async throws {
        let github = FakeTransport([
            .json(200, releaseJSON("v2.0.0", ["tool-windows-x64.zip"])),
            .json(200, "[\(releaseJSON("v2.0.0", ["tool-windows-x64.zip"])), \(releaseJSON("v1.9.0", ["tool.dmg"]))]"),
        ])

        let release = try await GitHubClient(transport: github, token: nil).latestRelease(repoURL: repo, filter: nil)

        XCTAssertEqual(release.version, "1.9.0")
        XCTAssertEqual(github.requests[1].target, "/repos/owner/tool/releases?per_page=10")
    }

    func testARepositoryWithoutReleasesIsTrackedByItsFonts() async throws {
        let tree = #"{"truncated": false, "tree": [{"path": "fonts/C64 Keyboard.ttf", "type": "blob", "size": 9000}]}"#
        let github = FakeTransport([
            .json(404, "{}"), .json(200, "[]"), .json(200, tree),
            .file(TestFonts.font(declaring: "1.107")), .file(TestFonts.font(declaring: "1.107")),
        ])

        let release = try await GitHubClient(transport: github, token: "ghp_token").latestRelease(repoURL: repo, filter: nil)

        XCTAssertEqual(release.version, "1.107")
        XCTAssertEqual(release.downloadURL, "https://raw.githubusercontent.com/owner/tool/HEAD/fonts/C64%20Keyboard.ttf")
        XCTAssertEqual(github.requests[2].target, "/repos/owner/tool/git/trees/HEAD?recursive=1")
        // Raw file reads leave the API, so they carry no token.
        XCTAssertNil(github.requests[3].authorization)
    }

    func testAnEmptyRepositoryReportsNoPublishedReleases() async {
        let github = FakeTransport([.json(404, "{}"), .json(200, "[]"), .json(409, "{}")])
        do {
            _ = try await GitHubClient(transport: github, token: nil).latestRelease(repoURL: repo, filter: nil)
            XCTFail("found a release")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("No published releases"), error.localizedDescription)
        }
    }

    func testStatusFailuresAreClassified() async {
        let limited = FakeTransport([.chunks(403, [Data("{}".utf8)])])
        do {
            _ = try await GitHubClient(transport: limited, token: nil).latestRelease(repoURL: repo, filter: nil)
            XCTFail("found a release")
        } catch {
            XCTAssertEqual(error.localizedDescription, "GitHub API error: 403 Forbidden")
            XCTAssertEqual((error as? LookupFailure)?.kind, .permissionDenied)
        }

        XCTAssertEqual(GitHubClient.statusFailure(HTTPResponse(status: 403, headers: ["x-ratelimit-remaining": "0"],
                                                               body: Data())).kind, .rateLimited)
        XCTAssertEqual(GitHubClient.statusFailure(HTTPResponse(status: 500, headers: [:], body: Data())).kind, .failed)
    }

    func testABudgetStopsRequestsBeforeTheyAreSent() async {
        let github = FakeTransport([.json(200, releaseJSON("v1.0.0", ["tool.dmg"]))])
        let budget = GitHubRateBudget(maximumRequests: 0)
        do {
            _ = try await GitHubClient(transport: github, token: nil, budget: budget).latestRelease(repoURL: repo, filter: nil)
            XCTFail("sent a request")
        } catch {
            XCTAssertEqual((error as? LookupFailure)?.kind, .rateLimited)
            XCTAssertTrue(github.requests.isEmpty)
        }
    }

    func testTheBudgetKeepsGitHubsReserve() async throws {
        let budget = GitHubRateBudget(maximumRequests: 10, keepInReserve: 10)
        try await budget.spend()
        await budget.record(headers: ["x-ratelimit-remaining": "11"])
        try await budget.spend()
        await budget.record(headers: ["x-ratelimit-remaining": "10"])
        do {
            try await budget.spend()
            XCTFail("spent the reserve")
        } catch {
            XCTAssertEqual((error as? LookupFailure)?.kind, .rateLimited)
        }
    }

    func testANetworkFailureNamesWhatItInterrupted() async {
        let github = FakeTransport([.failure(URLError(.notConnectedToInternet))])
        do {
            _ = try await GitHubClient(transport: github, token: nil).latestRelease(repoURL: repo, filter: nil)
            XCTFail("found a release")
        } catch {
            XCTAssertTrue(error.localizedDescription.hasPrefix("Failed to fetch GitHub release: "), error.localizedDescription)
            XCTAssertEqual((error as? LookupFailure)?.kind, .unreachable)
        }
    }

    func testGitLabIsUnsupported() async {
        let lookup = ReleaseLookup(transport: FakeTransport([]))
        let app = TrackedApp(id: "id", name: "Lab", sourceType: .gitlab, sourceURL: "https://gitlab.com/o/r")
        do {
            _ = try await lookup.latestRelease(of: app, credentials: LookupCredentials(), budget: nil)
            XCTFail("found a release")
        } catch {
            XCTAssertEqual((error as? LookupFailure)?.kind, .unsupported)
            XCTAssertEqual(error.localizedDescription, "GitLab support not yet implemented")
        }
    }

    func testAHandEditedFilterIsReportedNotIgnored() async {
        let lookup = ReleaseLookup(transport: FakeTransport([]))
        let app = TrackedApp(id: "id", name: "Tool", sourceType: .github, sourceURL: "https://github.com/o/r",
                             assetFilter: "*")
        do {
            _ = try await lookup.latestRelease(of: app, credentials: LookupCredentials(), budget: nil)
            XCTFail("found a release")
        } catch {
            XCTAssertTrue(error.localizedDescription.hasPrefix("The stored program filter is invalid"),
                          error.localizedDescription)
        }
    }
}
