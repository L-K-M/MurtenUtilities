import XCTest
@testable import ObtainintoshCore

final class ReleaseSelectionTests: XCTestCase {
    /// Hauntware 1.9.0: four programs in one release, for every platform.
    static let hauntwareAssets = [
        "planchette-linux-x64.AppImage", "planchette-linux-x64.flatpak", "planchette-linux-x64.tar.gz",
        "planchette-macos-universal.zip", "planchette-windows-x64.zip", "planchette_1.9.0-1_amd64.deb",
        "poltergeist-android.apk", "poltergeist-ios-unsigned.ipa", "poltergeist-linux-x64.AppImage",
        "poltergeist-macos-universal.zip", "poltergeist-windows-x64.zip", "poltergeist_1.9.0-1_amd64.deb",
        "seance-linux-x64.AppImage", "seance-linux-x64.tar.gz", "seance-macos-universal.zip",
        "seance-sync-linux-x64.tar.gz", "seance-sync-macos-arm64.tar.gz", "seance-sync-windows-x64.tar.gz",
        "seance-windows-x64.zip", "seance_1.9.0-1_amd64.deb", "SHA256SUMS",
    ]

    /// An asset name every Mac accepts, whatever its CPU.
    static func compatibleAssetName(_ stem: String) -> String {
        "\(stem)-macos-universal.dmg"
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json",
                                                  subdirectory: "Fixtures/github"))
        return try Data(contentsOf: url)
    }

    private func release(_ tag: String, prerelease: Bool = false, draft: Bool = false,
                         _ assets: [String]) -> ForgeRelease {
        ForgeRelease(tagName: tag, assets: assets.map { ReleaseAsset(name: $0, browserDownloadURL: "url", size: 100) },
                     draft: draft, prerelease: prerelease)
    }

    private func program(_ name: String) throws -> AssetFilter {
        try XCTUnwrap(try AssetFilter.parse(name))
    }

    // MARK: - Fixtures

    func testLatestWithoutACompatibleAssetFallsBackToAnOlderStableRelease() throws {
        let latest = try JSONDecoder().decode(ForgeRelease.self, from: fixture("latest-missing-compatible-asset"))
        XCTAssertFalse(latest.hasCompatibleAsset(filter: nil), "fixture should lack a compatible asset")

        let releases = try JSONDecoder().decode([ForgeRelease].self, from: fixture("older-stable-valid"))
        let selected = try ReleaseSelection.selectRecentRelease(releases, stableReleasePublished: true, filter: nil)

        // The newer prerelease is skipped: the user tracks the stable channel.
        XCTAssertEqual(selected.tagName, "v1.9.0")
        XCTAssertEqual(try selected.buildRelease(filter: nil).version, "1.9.0")
    }

    func testARepositoryWithOnlyPrereleasesSelectsACompatiblePrerelease() throws {
        let releases = try JSONDecoder().decode([ForgeRelease].self, from: fixture("prerelease-only"))
        // stableReleasePublished false: `releases/latest` 404d.
        let selected = try ReleaseSelection.selectRecentRelease(releases, stableReleasePublished: false, filter: nil)
        XCTAssertEqual(selected.tagName, "v4.0.0-beta.1")
    }

    func testDraftsAreNeverSelected() throws {
        let releases = try JSONDecoder().decode([ForgeRelease].self, from: fixture("draft-exclusion"))
        let selected = try ReleaseSelection.selectRecentRelease(releases, stableReleasePublished: true, filter: nil)
        XCTAssertEqual(selected.tagName, "v2.9.0", "a draft was selected")
    }

    func testNoCompatibleStableReleaseDoesNotSilentlySwitchChannel() throws {
        let releases = try JSONDecoder().decode([ForgeRelease].self, from: fixture("no-compatible-stable-release"))

        XCTAssertThrowsError(try ReleaseSelection.selectRecentRelease(releases, stableReleasePublished: true,
                                                                      filter: nil)) { error in
            XCTAssertTrue("\(error)".contains("No macOS-compatible stable release found in the 10 most recent releases"),
                          "\(error)")
        }
        // The prerelease is installable: it is withheld on purpose, not missed.
        XCTAssertNotNil(ReleaseSelection.findCompatibleRelease(releases, prerelease: true, filter: nil))
    }

    func testWithoutAStableReleaseAnyPublishedChannelIsAcceptable() throws {
        let releases = try JSONDecoder().decode([ForgeRelease].self, from: fixture("no-compatible-stable-release"))
        let selected = try ReleaseSelection.selectRecentRelease(releases, stableReleasePublished: false, filter: nil)
        XCTAssertEqual(selected.tagName, "v5.1.0-beta.1")
    }

    // MARK: - Unpublished repositories

    func testAnEmptyReleaseListNamesTheAbsenceOfPublishedReleases() {
        XCTAssertThrowsError(try ReleaseSelection.selectRecentRelease([], stableReleasePublished: false,
                                                                      filter: nil)) { error in
            let message = "\(error)"
            XCTAssertTrue(message.contains("No published releases"), message)
            XCTAssertTrue(message.contains("draft"), message)
            XCTAssertFalse(message.contains("compatible"), message)
        }
    }

    func testAListOfOnlyDraftsNamesTheAbsenceOfPublishedReleases() {
        let releases = ["v2.0.0", "v1.9.0"].map { release($0, draft: true, [Self.compatibleAssetName("App")]) }
        XCTAssertThrowsError(try ReleaseSelection.selectRecentRelease(releases, stableReleasePublished: false,
                                                                      filter: nil)) { error in
            XCTAssertTrue("\(error)".contains("No published releases"), "\(error)")
        }
    }

    func testAnAllDraftWindowKeepsTheStableChannelMessageWhenLatestAnswered() {
        let releases = [release("v2.0.0", draft: true, [Self.compatibleAssetName("App")])]
        XCTAssertThrowsError(try ReleaseSelection.selectRecentRelease(releases, stableReleasePublished: true,
                                                                      filter: nil)) { error in
            XCTAssertTrue("\(error)".contains("stable"), "\(error)")
            XCTAssertFalse("\(error)".contains("No published releases"), "\(error)")
        }
    }

    // MARK: - Programs

    func testReleaseProgramsAreTheOnesThisMacCanInstall() {
        let programs = release("v1.9.0", [Self.compatibleAssetName("seance"), Self.compatibleAssetName("planchette"),
                                          "seance-windows-x64.zip", "poltergeist-windows-x64.zip", "SHA256SUMS"])
            .programs()

        XCTAssertEqual(programs.version, "1.9.0")
        XCTAssertEqual(programs.programs, ["planchette", "seance"])
        XCTAssertEqual(programs.defaultProgram, "planchette")
    }

    func testAFilteredProgramMissingFromTheNewestReleaseComesFromAnOlderOne() throws {
        let releases = [
            release("v2.0.0", [Self.compatibleAssetName("planchette")]),
            release("v1.9.0", [Self.compatibleAssetName("planchette"), Self.compatibleAssetName("seance")]),
        ]
        let seance = try program("seance")

        XCTAssertFalse(releases[0].hasCompatibleAsset(filter: seance))
        let selected = try ReleaseSelection.selectRecentRelease(releases, stableReleasePublished: true, filter: seance)

        XCTAssertEqual(selected.tagName, "v1.9.0")
        XCTAssertEqual(try selected.buildRelease(filter: seance).fileName, Self.compatibleAssetName("seance"))
    }

    func testAMissingProgramIsReportedWithWhatTheNewestReleaseOffers() throws {
        let releases = [
            release("v2.1.0-beta.1", prerelease: true, [Self.compatibleAssetName("beta-only")]),
            release("v2.0.0", [Self.compatibleAssetName("seance"), Self.compatibleAssetName("planchette")]),
        ]
        // Misspelt on purpose: the filter must match no program.
        XCTAssertThrowsError(try ReleaseSelection.selectRecentRelease(releases, stableReleasePublished: true,
                                                                      filter: try program("seanse"))) { error in
            let message = "\(error)"
            // The listing follows the tracked channel.
            XCTAssertTrue(message.contains("stable release of \"seanse\""), message)
            XCTAssertTrue(message.hasSuffix("The newest offers: planchette, seance"), message)
        }
    }

    func testAMissingProgramIsReportedEvenWhenTheNewestReleaseOffersNothingHere() throws {
        let releases = [release("v2.0.0", ["seance-windows-x64.zip"])]
        XCTAssertThrowsError(try ReleaseSelection.selectRecentRelease(releases, stableReleasePublished: true,
                                                                      filter: try program("seance"))) { error in
            XCTAssertTrue("\(error)".hasSuffix("The newest offers nothing for macOS"), "\(error)")
        }
    }

    func testListedProgramsAreSummarisedPastTheLimit() {
        let programs = ["a", "b", "c", "d", "e", "f", "g"]
        XCTAssertEqual(ReleaseSelection.listPrograms(Array(programs.prefix(2))), "a, b")
        XCTAssertEqual(ReleaseSelection.listPrograms(Array(programs.prefix(5))), "a, b, c, d, e")
        XCTAssertEqual(ReleaseSelection.listPrograms(Array(programs.prefix(6))), "a, b, c, d, e and 1 more")
        XCTAssertEqual(ReleaseSelection.listPrograms(programs), "a, b, c, d, e and 2 more")
    }

    // MARK: - Decoding and tags

    func testTheReleaseShapeIsSharedByBothForges() throws {
        // A Forgejo payload decodes like a GitHub one; extra fields are ignored.
        let payload = """
        {
            "tag_name": "v2.1.0", "body": "notes", "draft": false, "prerelease": false,
            "html_url": "https://git.example.internal/owner/repo/releases/tag/v2.1.0",
            "assets": [
                {"id": 7, "name": "App-macos-universal.dmg", "size": 4096, "uuid": "8e0f",
                 "browser_download_url": "https://git.example.internal/owner/repo/releases/download/v2.1.0/App-macos-universal.dmg"},
                {"id": 8, "name": "App.AppImage", "size": 4096, "uuid": "8e10",
                 "browser_download_url": "https://git.example.internal/owner/repo/releases/download/v2.1.0/App.AppImage"}
            ]
        }
        """
        let release = try JSONDecoder().decode(ForgeRelease.self, from: Data(payload.utf8)).buildRelease(filter: nil)
        XCTAssertEqual(release.version, "2.1.0")
        XCTAssertEqual(release.fileName, Self.compatibleAssetName("App"))
        XCTAssertEqual(release.fileSize, 4096)
        XCTAssertEqual(release.releaseNotes, "notes")
        XCTAssertTrue(release.downloadURL.hasPrefix("https://git.example.internal/"))
    }

    func testCleanVersionTag() {
        XCTAssertEqual(ReleaseSelection.cleanVersionTag("v1.2.3"), "1.2.3")
        XCTAssertEqual(ReleaseSelection.cleanVersionTag("1.2.3"), "1.2.3")
        XCTAssertEqual(ReleaseSelection.cleanVersionTag("V2.0"), "2.0")
        XCTAssertEqual(ReleaseSelection.cleanVersionTag("version-2"), "version-2")
        XCTAssertEqual(ReleaseSelection.cleanVersionTag("vapor"), "vapor")
    }
}
