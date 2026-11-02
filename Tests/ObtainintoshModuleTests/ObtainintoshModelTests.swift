import XCTest
import MurtenCore
import ObtainintoshCore
@testable import ObtainintoshModule
@testable import ObtainintoshServices

@MainActor
final class ObtainintoshModelTests: XCTestCase {
    private func release(_ version: String, _ file: String = "Tool.dmg") -> Result<Release, Error> {
        .success(Release(version: version, downloadURL: "https://github.com/o/tool/releases/download/v\(version)/\(file)",
                         fileName: file, fileSize: 10))
    }

    // MARK: - Adding and removing

    func testAddingKeepsTheKeyInTheKeychainNotTheFile() async throws {
        let fixture = Fixture()
        fixture.detector.installed["Private"] = InstalledVersion(path: "/Applications/Private.app", version: "1.0")
        let model = fixture.model()
        model.load()

        try await model.add(SourceInput(url: "https://git.example.internal/o/private", name: "Private",
                                        sourceType: .forgejo, username: "alice", accessToken: "key123"))

        let app = try XCTUnwrap(model.apps.first)
        XCTAssertTrue(app.hasStoredAccessToken)
        XCTAssertNil(app.accessToken)
        XCTAssertEqual(app.currentVersion, "1.0")
        XCTAssertEqual(fixture.secrets.stored["forgejo-key.\(app.id)"], "key123")
        let file = try String(contentsOf: fixture.listURL, encoding: .utf8)
        XCTAssertFalse(file.contains("key123"), file)
    }

    func testAddingTheSameRepositoryTwiceIsRefused() async throws {
        let model = Fixture().model()
        try await model.add(SourceInput(url: "https://github.com/o/tool", name: "Tool"))
        do {
            try await model.add(SourceInput(url: "https://github.com/O/tool.git", name: "Tool"))
            XCTFail("added a duplicate")
        } catch {
            XCTAssertEqual(error.localizedDescription, "This repository is already being tracked")
        }
    }

    func testRemovingLeavesATombstoneAndDropsTheKey() async throws {
        let fixture = Fixture()
        let model = fixture.model()
        try await model.add(SourceInput(url: "https://codeberg.org/o/private", name: "Private", sourceType: .forgejo,
                                        accessToken: "key123"))
        let id = try XCTUnwrap(model.apps.first?.id)

        await model.remove(id: id)

        XCTAssertTrue(model.apps.isEmpty)
        XCTAssertNil(fixture.secrets.stored["forgejo-key.\(id)"])
        XCTAssertEqual(try TrackedListStore.readSnapshot(at: fixture.listURL)?.removedAppIDs, [id])
    }

    func testChecksAndRemovalsAskForAPromptBackgroundCheck() async throws {
        let fixture = Fixture()
        let model = fixture.model()
        try await model.add(SourceInput(url: "https://github.com/o/tool", name: "Tool"))
        XCTAssertEqual(fixture.recheckRequests, 0, "adding changes nothing a suggestion reports")

        fixture.lookup.releases["https://github.com/o/tool"] = release("2.0")
        await model.checkForUpdates()
        XCTAssertEqual(fixture.recheckRequests, 1)

        await model.remove(id: try XCTUnwrap(model.apps.first?.id))
        XCTAssertEqual(fixture.recheckRequests, 2)
    }

    func testEditingAwayFromForgejoRemovesTheKey() async throws {
        let fixture = Fixture()
        let model = fixture.model()
        try await model.add(SourceInput(url: "https://codeberg.org/o/tool", name: "Tool", sourceType: .forgejo,
                                        accessToken: "key123"))
        let id = try XCTUnwrap(model.apps.first?.id)

        try await model.update(id: id, with: SourceInput(url: "https://github.com/o/tool", name: "Tool",
                                                         sourceType: .github, accessToken: "key123"))

        XCTAssertFalse(model.apps[0].hasStoredAccessToken)
        XCTAssertNil(fixture.secrets.stored["forgejo-key.\(id)"])
    }

    // MARK: - Checking

    func testACheckRecordsReleasesAndReportsFailures() async throws {
        let fixture = Fixture(secrets: ["forgejo-key.unused": "x"])
        fixture.detector.installed["Tool"] = InstalledVersion(path: "/Applications/Tool.app", version: "1.0")
        fixture.lookup.releases["https://github.com/o/tool"] = release("2.0")
        let model = fixture.model()
        try await model.add(SourceInput(url: "https://github.com/o/tool", name: "Tool"))
        try await model.add(SourceInput(url: "https://github.com/o/broken", name: "Broken"))

        await model.checkForUpdates(quiet: true)

        let tool = try XCTUnwrap(model.apps.first { $0.name == "Tool" })
        XCTAssertEqual(tool.latestVersion, "2.0")
        XCTAssertEqual(ProgramStatus(tool), .updateAvailable)
        let broken = try XCTUnwrap(model.apps.first { $0.name == "Broken" })
        XCTAssertEqual(broken.lastCheckAttempt?.state, .failed)
        XCTAssertEqual(model.notices.last?.text, "Broken: no fixture for https://github.com/o/broken")
        XCTAssertEqual(model.notices.last?.kind, .error)
        XCTAssertFalse(model.isChecking)
        XCTAssertNil(model.checkProgress)
    }

    func testAQuietCheckThatSucceedsSaysNothing() async throws {
        let fixture = Fixture()
        fixture.lookup.releases["https://github.com/o/tool"] = release("2.0")
        let model = fixture.model()
        try await model.add(SourceInput(url: "https://github.com/o/tool", name: "Tool"))
        let before = model.notices.count

        await model.checkForUpdates(quiet: true)
        XCTAssertEqual(model.notices.count, before)

        await model.checkForUpdates()
        XCTAssertEqual(model.notices.last?.text, "Update check completed")
    }

    func testAPrivateProgramsKeyIsReadForTheCheck() async throws {
        let fixture = Fixture()
        fixture.lookup.releases["https://codeberg.org/o/private"] = release("2.0")
        let model = fixture.model()
        try await model.add(SourceInput(url: "https://codeberg.org/o/private", name: "Private", sourceType: .forgejo,
                                        accessToken: "key123"))

        await model.checkForUpdates(quiet: true)

        XCTAssertEqual(fixture.lookup.lookups.last?.key, "key123")
    }

    // MARK: - Downloading

    func testADownloadIsRecordedAndRevealedNeverInstalled() async throws {
        let fixture = Fixture()
        fixture.lookup.releases["https://github.com/o/tool"] = release("2.0")
        let model = fixture.model()
        try await model.add(SourceInput(url: "https://github.com/o/tool", name: "Tool"))
        let id = try XCTUnwrap(model.apps.first?.id)

        model.download(id: id)
        for _ in 0..<200 where model.apps.first?.downloaded == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let downloaded = try XCTUnwrap(model.apps.first?.downloaded)
        XCTAssertEqual(downloaded.version, "2.0")
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloaded.path))
        XCTAssertEqual(fixture.revealer.revealed.map(\.path), [downloaded.path])
        XCTAssertEqual(ProgramAction(model.apps[0]), .revealDownload)
    }

    func testAVanishedDownloadIsForgotten() async throws {
        let fixture = Fixture()
        let model = fixture.model()
        try await model.add(SourceInput(url: "https://github.com/o/tool", name: "Tool"))
        let store = try TrackedListStore(fileURL: fixture.listURL)
        var app = try XCTUnwrap(store.apps.first)
        app.downloaded = DownloadedRelease(version: "2.0", path: fixture.folder.appendingPathComponent("gone.dmg").path)
        try store.update(app)

        let reloaded = fixture.model()
        reloaded.load()

        XCTAssertNil(reloaded.apps.first?.downloaded)
    }

    // MARK: - The standalone app's list

    func testTheStandaloneListIsOfferedImportedAndLeftUntouched() async throws {
        let fixture = Fixture()
        let standalone = #"{"apps":[{"id":"a1","name":"Private","source_type":"forgejo","source_url":"https://codeberg.org/o/private","username":"alice","access_token":"key123","latest_version":"1.0"},{"id":"a2","name":"Tool","source_type":"github","source_url":"https://github.com/o/tool"}],"settings":{"github_token":"ghp_secret","gitlab_token":null},"self_entry_seeded":true}"#
        fixture.writeStandalone(standalone)
        let model = fixture.model()

        model.paneAppeared(route: nil)
        XCTAssertEqual(model.standaloneOffer, 2)

        await model.importStandaloneList()

        XCTAssertNil(model.standaloneOffer)
        XCTAssertEqual(model.apps.map(\.id).sorted(), ["a1", "a2"])
        XCTAssertEqual(model.apps.first { $0.id == "a1" }?.latestVersion, "1.0")
        XCTAssertEqual(fixture.secrets.stored["forgejo-key.a1"], "key123")
        XCTAssertEqual(fixture.secrets.stored["github-token"], "ghp_secret")
        XCTAssertEqual(try String(contentsOf: fixture.standaloneURL, encoding: .utf8), standalone)
        let suiteFile = try String(contentsOf: fixture.listURL, encoding: .utf8)
        XCTAssertFalse(suiteFile.contains("key123") || suiteFile.contains("ghp_secret"), suiteFile)

        // Once decided, the offer does not come back.
        model.refreshStandaloneOffer()
        XCTAssertNil(model.standaloneOffer)
    }

    func testDecliningTheStandaloneListImportsNothing() {
        let fixture = Fixture()
        fixture.writeStandalone(#"{"apps":[{"id":"a","name":"Tool","source_type":"github","source_url":"https://github.com/o/tool"}]}"#)
        let model = fixture.model()

        model.refreshStandaloneOffer()
        XCTAssertEqual(model.standaloneOffer, 1)
        model.declineStandaloneImport()

        XCTAssertNil(model.standaloneOffer)
        model.refreshStandaloneOffer()
        XCTAssertNil(model.standaloneOffer)
        XCTAssertTrue(model.apps.isEmpty)
    }

    // MARK: - Export and import

    func testAnExportedListImportsIntoAnotherSuite() async throws {
        let source = Fixture()
        let model = source.model()
        try await model.add(SourceInput(url: "https://codeberg.org/o/private", name: "Private", sourceType: .forgejo,
                                        username: "alice", accessToken: "key123"))
        let contents = try XCTUnwrap(model.exportContents())
        let file = source.folder.appendingPathComponent("list")
        model.writeExport(contents, to: file)
        let written = file.appendingPathExtension("obtainintosh")
        XCTAssertFalse(try String(contentsOf: written, encoding: .utf8).contains("key123"))

        let target = Fixture()
        let other = target.model()
        await other.importList(from: written)

        XCTAssertEqual(other.apps.map(\.name), ["Private"])
        XCTAssertTrue(other.notices.contains { $0.text.contains("needs its application key") })
    }

    // MARK: - Opening from a suggestion

    func testASuggestionOpensACheckButNeverADownload() async throws {
        let fixture = Fixture()
        fixture.detector.installed["Tool"] = InstalledVersion(path: "/Applications/Tool.app", version: "1.0")
        fixture.lookup.releases["https://github.com/o/tool"] = release("2.0")
        let model = fixture.model()
        try await model.add(SourceInput(url: "https://github.com/o/tool", name: "Tool"))

        model.paneAppeared(route: "updates")
        for _ in 0..<200 where model.apps.first?.latestVersion == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(model.apps.first?.latestVersion, "2.0")
        XCTAssertNil(model.apps.first?.downloaded)
        XCTAssertTrue(fixture.revealer.revealed.isEmpty)
    }
}
