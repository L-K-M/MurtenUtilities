import XCTest
import ObtainintoshCore
@testable import ObtainintoshServices

/// The standalone app's Forgejo adapter tests, against a fake forge.
final class ForgejoClientTests: XCTestCase {
    private let basicAliceKey = "Basic YWxpY2U6a2V5MTIz"

    private func compatible(_ stem: String) -> String { "\(stem)-macos-universal.dmg" }

    private func releaseJSON(_ tag: String, draft: Bool = false, _ assets: [String]) -> String {
        let list = assets.map {
            #"{"name": "\#($0)", "size": 1024, "browser_download_url": "https://forge.invalid/download/\#($0)"}"#
        }
        return #"{"tag_name": "\#(tag)", "body": "notes for \#(tag)", "draft": \#(draft), "prerelease": false, "assets": [\#(list.joined(separator: ","))]}"#
    }

    private func treeJSON(_ paths: [String], total: Int) -> String {
        let entries = paths.map { #"{"path": "\#($0)", "type": "blob", "size": 4096}"# }
        return #"{"tree": [\#(entries.joined(separator: ","))], "total_count": \#(total), "truncated": true}"#
    }

    private func fontReleaseJSON(_ tag: String, _ asset: String) -> String {
        #"{"tag_name": "\#(tag)", "body": null, "draft": false, "prerelease": false, "assets": [{"name": "\#(asset)", "size": 4096, "browser_download_url": "{address}/owner/repo/releases/download/\#(tag)/\#(asset)"}]}"#
    }

    private func client(_ transport: FakeTransport, username: String? = nil, token: String? = nil) -> ForgejoClient {
        ForgejoClient(transport: transport, credentials: ForgeCredentials(username: username, token: token))
    }

    private func program(_ name: String) throws -> AssetFilter {
        try XCTUnwrap(try AssetFilter.parse(name))
    }

    func testReadsTheLatestReleaseWithCredentials() async throws {
        let forge = FakeTransport([.json(200, releaseJSON("v1.4.0", [compatible("App")]))])

        let release = try await client(forge, username: "alice", token: "key123")
            .latestRelease(repoURL: "\(forge.address)/owner/repo", filter: nil)

        XCTAssertEqual(release.version, "1.4.0")
        XCTAssertEqual(release.fileName, compatible("App"))
        XCTAssertEqual(release.fileSize, 1024)
        XCTAssertEqual(forge.requests.count, 1)
        XCTAssertEqual(forge.requests[0].target, "/api/v1/repos/owner/repo/releases/latest")
        XCTAssertEqual(forge.requests[0].authorization, basicAliceKey)
    }

    func testFallsBackToTheReleaseList() async throws {
        // `releases/latest` 404s for a repository that only publishes prereleases.
        let forge = FakeTransport([
            .json(404, "{}"),
            .json(200, "[\(releaseJSON("v2.0.0-rc.1", draft: true, [compatible("Draft")])), "
                + "\(releaseJSON("v1.9.0", [compatible("App")]))]"),
        ])

        let release = try await client(forge).latestRelease(repoURL: "\(forge.address)/owner/repo", filter: nil)

        // The draft is skipped, so the newest published release wins.
        XCTAssertEqual(release.version, "1.9.0")
        XCTAssertEqual(forge.requests.count, 2)
        XCTAssertEqual(forge.requests[1].target, "/api/v1/repos/owner/repo/releases?limit=10")
        // Nothing to authenticate with, so nothing is sent.
        XCTAssertNil(forge.requests[1].authorization)
    }

    func testAMissingRepositoryPointsAtTheCredentials() async {
        // A private repository the credentials cannot see 404s like a missing
        // one: latest release, release list, file listing and repository.
        let forge = FakeTransport(Array(repeating: .json(404, "{}"), count: 4))

        do {
            _ = try await client(forge).latestRelease(repoURL: "\(forge.address)/owner/repo", filter: nil)
            XCTFail("found a release")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("application key"), error.localizedDescription)
            XCTAssertEqual((error as? LookupFailure)?.kind, .permissionDenied)
        }
    }

    func testRejectedCredentialsAreReportedPlainly() async {
        let forge = FakeTransport([.json(401, "{}")])
        do {
            _ = try await client(forge, username: "alice", token: "wrong")
                .latestRelease(repoURL: "\(forge.address)/owner/repo", filter: nil)
            XCTFail("found a release")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("401"), error.localizedDescription)
            XCTAssertTrue(error.localizedDescription.contains("username and application key"), error.localizedDescription)
        }
    }

    func testListsTheProgramsAndResolvesOneFromTheLatestRelease() async throws {
        let latest = releaseJSON("v2.0.0", [compatible("planchette"), compatible("seance")])
        let forge = FakeTransport([.json(200, latest), .json(200, latest)])
        let url = "\(forge.address)/owner/repo"

        let programs = try await client(forge).releasePrograms(repoURL: url)
        let seance = try await client(forge).latestRelease(repoURL: url, filter: try program("seance"))

        XCTAssertEqual(programs.programs, ["planchette", "seance"])
        XCTAssertEqual(programs.defaultProgram, "planchette")
        XCTAssertEqual(seance.fileName, compatible("seance"))
        // The latest release has the program, so the list is never read.
        XCTAssertEqual(forge.requests.count, 2)
        XCTAssertTrue(forge.requests.allSatisfy { $0.target.hasSuffix("/releases/latest") })
    }

    func testFindsAFilteredProgramInAnOlderRelease() async throws {
        let latest = releaseJSON("v2.0.0", [compatible("planchette")])
        let list = "[\(latest), \(releaseJSON("v1.9.0", [compatible("planchette"), compatible("seance")]))]"
        let forge = FakeTransport([.json(200, latest), .json(200, list)])

        let release = try await client(forge).latestRelease(repoURL: "\(forge.address)/owner/repo",
                                                            filter: try program("seance"))

        XCTAssertEqual(release.version, "1.9.0")
        XCTAssertEqual(release.fileName, compatible("seance"))
        XCTAssertEqual(forge.requests.count, 2)
    }

    func testReadsACommittedFontWhenThereAreNoReleases() async throws {
        let forge = FakeTransport([
            .json(404, "{}"),
            .json(200, "[]"),
            .json(200, treeJSON(["README.md", "fonts/My Font-Regular.ttf"], total: 2)),
            .file(TestFonts.font(declaring: "1.107")),
            .file(TestFonts.font(declaring: "1.107")),
        ])

        let release = try await client(forge, username: "alice", token: "key123")
            .latestRelease(repoURL: "\(forge.address)/owner/repo", filter: nil)

        XCTAssertEqual(release.version, "1.107")
        XCTAssertEqual(release.fileName, "My Font-Regular.ttf")
        XCTAssertEqual(release.fileSize, 4096)
        XCTAssertEqual(release.downloadURL, "\(forge.address)/api/v1/repos/owner/repo/raw/fonts/My%20Font-Regular.ttf")

        let requests = forge.requests
        XCTAssertEqual(requests[2].target,
                       "/api/v1/repos/owner/repo/git/trees/HEAD?recursive=true&per_page=1000&page=1")
        // The version comes from two small reads, authenticated like the download.
        XCTAssertEqual(requests[3].range, "bytes=0-4095")
        XCTAssertNotNil(requests[4].range)
        XCTAssertEqual(requests.count, 5)
        XCTAssertTrue(requests[3...].allSatisfy { $0.authorization != nil })
    }

    func testReadsTheFilesOfARepositoryWithReleasesTurnedOff() async throws {
        // Turned-off releases 404 like a missing repository; the paged file
        // listing tells them apart.
        let forge = FakeTransport([
            .json(404, "{}"),
            .json(404, "{}"),
            .json(200, treeJSON(["Abacus-Regular.otf", "OFL.txt"], total: 3)),
            .json(200, treeJSON(["Abacus-Bold.otf"], total: 3)),
            .file(TestFonts.font(declaring: "2.0")),
            .file(TestFonts.font(declaring: "2.0")),
        ])

        let programs = try await client(forge).releasePrograms(repoURL: "\(forge.address)/owner/repo")

        XCTAssertEqual(programs.version, "2.0")
        XCTAssertEqual(programs.programs, ["abacus-bold", "abacus-regular"])
        XCTAssertEqual(programs.defaultProgram, "abacus-bold")
        XCTAssertTrue(forge.requests[3].target.hasSuffix("&page=2"))
    }

    func testReadsFontVersionsFromServersThatIgnoreRanges() async throws {
        let font = TestFonts.font(declaring: "3.2")
        let forge = FakeTransport([
            .json(404, "{}"), .json(200, "[]"), .json(200, treeJSON(["Font.otf"], total: 1)),
            .wholeFile(font), .wholeFile(font),
        ])

        let release = try await client(forge).latestRelease(repoURL: "\(forge.address)/owner/repo", filter: nil)

        XCTAssertEqual(release.version, "3.2")
    }

    /// An installed font is compared by the version it declares, so a
    /// released font is too, whatever the tag says.
    func testReleasedFontsTakeTheVersionTheyDeclare() async throws {
        let forge = FakeTransport([
            .json(200, fontReleaseJSON("r2024-01", "Font-Regular.ttf")),
            .file(TestFonts.font(declaring: "1.107")),
            .file(TestFonts.font(declaring: "1.107")),
        ])

        let release = try await client(forge, username: "alice", token: "key123")
            .latestRelease(repoURL: "\(forge.address)/owner/repo", filter: nil)

        XCTAssertEqual(release.version, "1.107")
        XCTAssertEqual(release.fileName, "Font-Regular.ttf")
        XCTAssertEqual(forge.requests.count, 3)
        // Read on the instance, so with its credentials.
        XCTAssertNotNil(forge.requests[1].authorization)
    }

    func testAnUnreadableReleasedFontKeepsTheTag() async throws {
        let forge = FakeTransport([
            .json(200, fontReleaseJSON("v2.0", "Font-Regular.ttf")),
            .file(Array("version https://git-lfs.github.com/spec/v1".utf8)),
        ])

        let release = try await client(forge).latestRelease(repoURL: "\(forge.address)/owner/repo", filter: nil)

        XCTAssertEqual(release.version, "2.0")
    }

    func testReleasesTurnedOffWithoutFontsAreNamedAsSuch() async {
        // The files are listed, so the repository is visible.
        let forge = FakeTransport([.json(404, "{}"), .json(404, "{}"), .json(200, treeJSON(["README.md"], total: 1))])
        do {
            _ = try await client(forge).latestRelease(repoURL: "\(forge.address)/owner/repo", filter: nil)
            XCTFail("found a release")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("releases turned off"), error.localizedDescription)
            XCTAssertFalse(error.localizedDescription.contains("application key"), error.localizedDescription)
        }
    }

    func testAnEmptyRepositoryWithReleasesTurnedOffIsFound() async {
        let forge = FakeTransport([.json(404, "{}"), .json(404, "{}"), .json(404, "{}"), .json(200, "{}")])
        do {
            _ = try await client(forge).latestRelease(repoURL: "\(forge.address)/owner/repo", filter: nil)
            XCTFail("found a release")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("releases turned off"), error.localizedDescription)
            XCTAssertEqual(forge.requests[3].target, "/api/v1/repos/owner/repo")
        }
    }

    func testDownloadCredentialsArePinnedToTheInstance() throws {
        let auth = try client(FakeTransport([]), username: "alice", token: "key123")
            .downloadAuth(repoURL: "https://git.example.internal/owner/repo")
        XCTAssertEqual(auth.authorizationHeader(for: "https://git.example.internal/o/r/releases/download/v1/App.dmg"),
                       basicAliceKey)
        XCTAssertNil(auth.authorizationHeader(for: "https://cdn.example.com/App.dmg"))
    }
}
