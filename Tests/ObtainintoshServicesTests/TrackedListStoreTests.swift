import XCTest
import ObtainintoshCore
@testable import ObtainintoshServices

/// The standalone app's storage tests that concern the file: permissions,
/// atomic writes, symbolic links, corrupt files and failed writes.
final class TrackedListStoreTests: XCTestCase {
    private func app(_ id: String, _ url: String) -> TrackedApp {
        TrackedApp(id: id, name: id, sourceType: .github, sourceURL: url)
    }

    private func json(_ data: TrackedAppData) throws -> Data {
        try JSONEncoder().encode(data)
    }

    /// A store whose file lives under a folder that does not exist, so every
    /// write fails.
    private func failingStore(_ data: TrackedAppData, in folder: ScratchDirectory) -> TrackedListStore {
        TrackedListStore(fileURL: folder.path("missing/apps.json"), data: data)
    }

    func testTheFolderIsOwnerOnlyWhenCreatedOrTightened() throws {
        let folder = ScratchDirectory("store-folder")
        _ = try TrackedListStore(fileURL: folder.path("new/Obtainintosh/apps.json"))
        XCTAssertEqual(folder.mode("new/Obtainintosh"), 0o700)

        try FileManager.default.createDirectory(at: folder.path("existing"), withIntermediateDirectories: true)
        folder.setMode(0o777, "existing")
        _ = try TrackedListStore(fileURL: folder.path("existing/apps.json"))
        XCTAssertEqual(folder.mode("existing"), 0o700)
    }

    func testStartupTightensAnExistingFileWithoutRewritingIt() throws {
        let folder = ScratchDirectory("store-tighten")
        let original = try json(TrackedAppData(selfEntrySeeded: true))
        _ = FileManager.default.createFile(atPath: folder.path("apps.json").path, contents: original)
        folder.setMode(0o666, "apps.json")

        let store = try TrackedListStore(fileURL: folder.path("apps.json"))

        XCTAssertEqual(store.loadOutcome, .loaded)
        XCTAssertEqual(try Data(contentsOf: folder.path("apps.json")), original)
        XCTAssertEqual(folder.mode("apps.json"), 0o600)
    }

    func testStartupRejectsASymlinkWithoutTouchingItsTarget() throws {
        let folder = ScratchDirectory("store-symlink")
        let original = try json(TrackedAppData())
        _ = FileManager.default.createFile(atPath: folder.path("target.json").path, contents: original)
        folder.setMode(0o640, "target.json")
        try FileManager.default.createSymbolicLink(at: folder.path("apps.json"), withDestinationURL: folder.path("target.json"))

        XCTAssertThrowsError(try TrackedListStore(fileURL: folder.path("apps.json"))) {
            XCTAssertEqual("\($0)", "Refusing to use apps.json because it is a symbolic link")
        }
        XCTAssertEqual(try Data(contentsOf: folder.path("target.json")), original)
        XCTAssertEqual(folder.mode("target.json"), 0o640)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path("apps.json.corrupt-backup").path))
    }

    func testStartupRejectsANonRegularPath() throws {
        let folder = ScratchDirectory("store-directory")
        try FileManager.default.createDirectory(at: folder.path("apps.json"), withIntermediateDirectories: true)
        XCTAssertThrowsError(try TrackedListStore(fileURL: folder.path("apps.json"))) {
            XCTAssertEqual("\($0)", "Refusing to use apps.json because it is not a regular file")
        }
    }

    func testAnAtomicRewriteReplacesALooseFileWithAnOwnerOnlyOne() throws {
        let folder = ScratchDirectory("store-rewrite")
        _ = FileManager.default.createFile(atPath: folder.path("apps.json").path, contents: try json(TrackedAppData()))
        let store = try TrackedListStore(fileURL: folder.path("apps.json"))
        folder.setMode(0o666, "apps.json")

        _ = try store.addOne(app("", "https://github.com/owner/new"))

        XCTAssertEqual(folder.mode("apps.json"), 0o600)
        XCTAssertTrue(folder.temporaryFiles(of: "apps.json").isEmpty)
    }

    /// The old save wrote to a fixed `apps.json.tmp`, following a symlink there.
    func testAFixedTemporarySymlinkIsNotFollowed() throws {
        let folder = ScratchDirectory("store-temp-symlink")
        _ = FileManager.default.createFile(atPath: folder.path("victim").path, contents: Data("untouched".utf8))
        try FileManager.default.createSymbolicLink(at: folder.path("apps.json.tmp"), withDestinationURL: folder.path("victim"))
        let store = TrackedListStore(fileURL: folder.path("apps.json"), data: TrackedAppData())

        _ = try store.addOne(app("", "https://github.com/owner/new"))

        XCTAssertEqual(try String(contentsOf: folder.path("victim"), encoding: .utf8), "untouched")
        XCTAssertEqual(folder.temporaryFiles(of: "apps.json"), ["apps.json.tmp"])
        XCTAssertEqual(folder.mode("apps.json"), 0o600)
    }

    func testAFailedReplacementCleansItsTemporaryFile() throws {
        let folder = ScratchDirectory("store-failed-rename")
        try FileManager.default.createDirectory(at: folder.path("apps.json/inner"), withIntermediateDirectories: true)
        let store = TrackedListStore(fileURL: folder.path("apps.json"), data: TrackedAppData())

        XCTAssertThrowsError(try store.addOne(app("", "https://github.com/owner/new"))) {
            XCTAssertTrue("\($0)".contains("rename"), "\($0)")
        }
        XCTAssertTrue(folder.temporaryFiles(of: "apps.json").isEmpty)
    }

    func testFailedWritesDoNotChangeMemory() throws {
        let folder = ScratchDirectory("store-failing")
        let existing = app("existing", "https://github.com/owner/existing")
        let store = failingStore(TrackedAppData(apps: [existing]), in: folder)

        XCTAssertThrowsError(try store.addOne(app("", "https://github.com/owner/new"))) {
            XCTAssertEqual("\($0)", "Failed to write temp file")
        }
        XCTAssertThrowsError(try store.add([app("", "https://github.com/owner/one"), app("", "https://github.com/owner/two")]))
        var renamed = existing
        renamed.name = "Changed"
        XCTAssertThrowsError(try store.update(renamed))
        XCTAssertThrowsError(try store.remove(id: "existing"))

        XCTAssertEqual(store.apps, [existing])
    }

    func testABatchAddWritesOnceAfterTheExistingEntries() throws {
        let folder = ScratchDirectory("store-batch")
        _ = FileManager.default.createFile(atPath: folder.path("apps.json").path,
                                       contents: try json(TrackedAppData(apps: [app("existing", "https://github.com/owner/existing")])))
        let store = try TrackedListStore(fileURL: folder.path("apps.json"))

        let addition = try store.add([app("", "https://GitHub.com/owner/existing.git"), app("", "https://github.com/owner/new")])

        XCTAssertEqual(addition.added.count, 1)
        XCTAssertEqual(addition.duplicates.count, 1)
        let reloaded = try TrackedListStore(fileURL: folder.path("apps.json"))
        XCTAssertEqual(reloaded.apps.map(\.id), ["existing", addition.added[0].id])
    }

    func testABatchWithNothingNewLeavesTheFileAlone() throws {
        let folder = ScratchDirectory("store-nothing-new")
        let original = try json(TrackedAppData(apps: [app("existing", "https://github.com/owner/existing")]))
        _ = FileManager.default.createFile(atPath: folder.path("apps.json").path, contents: original)
        let store = try TrackedListStore(fileURL: folder.path("apps.json"))

        let addition = try store.add([app("", "https://github.com/owner/existing")])

        XCTAssertTrue(addition.added.isEmpty)
        XCTAssertEqual(try Data(contentsOf: folder.path("apps.json")), original)
    }

    func testForgottenDownloadsArePersisted() throws {
        let folder = ScratchDirectory("store-downloads")
        var gone = app("gone", "https://github.com/owner/gone")
        gone.downloaded = DownloadedRelease(version: "1.0", path: "/tmp/nowhere/App.dmg")
        var kept = app("kept", "https://github.com/owner/kept")
        kept.downloaded = DownloadedRelease(version: "2.0", path: "/tmp/still-there/App.dmg")
        _ = FileManager.default.createFile(atPath: folder.path("apps.json").path,
                                       contents: try json(TrackedAppData(apps: [gone, kept])))
        let store = try TrackedListStore(fileURL: folder.path("apps.json"))

        XCTAssertEqual(try store.forgetDownloads(["gone", "unknown"]), 1)

        let reloaded = try TrackedListStore(fileURL: folder.path("apps.json"))
        XCTAssertNil(reloaded.app(id: "gone")?.downloaded)
        XCTAssertNotNil(reloaded.app(id: "kept")?.downloaded)
    }

    func testMalformedJSONIsBackedUpBeforeRecovery() throws {
        let folder = ScratchDirectory("store-malformed")
        let malformed = Data("{ not valid json".utf8)
        _ = FileManager.default.createFile(atPath: folder.path("apps.json").path, contents: malformed)
        folder.setMode(0o666, "apps.json")

        let store = try TrackedListStore(fileURL: folder.path("apps.json"))

        guard case .recovered(let backup, _) = store.loadOutcome else { return XCTFail("\(store.loadOutcome)") }
        XCTAssertEqual(backup.lastPathComponent, "apps.json.corrupt-backup")
        XCTAssertEqual(try Data(contentsOf: backup), malformed)
        // Tightened before it was read, so the backup is owner-only too.
        XCTAssertEqual(folder.mode("apps.json.corrupt-backup"), 0o600)
        XCTAssertTrue(store.apps.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path("apps.json").path))
    }

    func testCorruptBackupsDoNotCollide() throws {
        let folder = ScratchDirectory("store-backups")
        _ = FileManager.default.createFile(atPath: folder.path("apps.json").path, contents: Data("first malformed file".utf8))
        _ = try TrackedListStore(fileURL: folder.path("apps.json"))
        _ = FileManager.default.createFile(atPath: folder.path("apps.json").path, contents: Data("second malformed file".utf8))
        _ = try TrackedListStore(fileURL: folder.path("apps.json"))

        XCTAssertEqual(try String(contentsOf: folder.path("apps.json.corrupt-backup"), encoding: .utf8), "first malformed file")
        XCTAssertEqual(try String(contentsOf: folder.path("apps.json.corrupt-backup.1"), encoding: .utf8),
                       "second malformed file")
    }

    func testValidDataLoadsWithoutRewritingOrBackup() throws {
        let folder = ScratchDirectory("store-valid")
        let valid = #"{"apps":[{"id":"valid-id","name":"Valid App","source_type":"github","source_url":"https://github.com/owner/valid","current_version":"1.0.0","latest_version":null,"install_path":"/Applications/Valid.app","last_checked":null}],"settings":{"github_token":null,"gitlab_token":null},"self_entry_seeded":true}"#
        _ = FileManager.default.createFile(atPath: folder.path("apps.json").path, contents: Data(valid.utf8))

        let store = try TrackedListStore(fileURL: folder.path("apps.json"))

        XCTAssertEqual(store.app(id: "valid-id")?.name, "Valid App")
        XCTAssertEqual(try String(contentsOf: folder.path("apps.json"), encoding: .utf8), valid)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path("apps.json.corrupt-backup").path))
    }

    func testTheFileNeverHoldsSecrets() throws {
        let folder = ScratchDirectory("store-secrets")
        let store = try TrackedListStore(fileURL: folder.path("apps.json"))
        var privateApp = TrackedApp(name: "Private", sourceType: .forgejo, sourceURL: "https://codeberg.org/o/private",
                                    username: "alice", accessToken: "key123")
        privateApp.hasStoredAccessToken = true

        _ = try store.addOne(privateApp)

        let written = try String(contentsOf: folder.path("apps.json"), encoding: .utf8)
        XCTAssertFalse(written.contains("key123"), written)
        XCTAssertTrue(written.contains("access_token_in_keychain"), written)
    }

    func testReadingASnapshotWritesNothing() throws {
        let folder = ScratchDirectory("store-snapshot")
        XCTAssertNil(try TrackedListStore.readSnapshot(at: folder.path("Obtainintosh/apps.json")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path("Obtainintosh").path))

        let original = try json(TrackedAppData(apps: [app("a", "https://github.com/o/a")]))
        _ = FileManager.default.createFile(atPath: folder.path("apps.json").path, contents: original)
        folder.setMode(0o644, "apps.json")
        XCTAssertEqual(try TrackedListStore.readSnapshot(at: folder.path("apps.json"))?.apps.map(\.id), ["a"])
        XCTAssertEqual(folder.mode("apps.json"), 0o644)

        _ = FileManager.default.createFile(atPath: folder.path("broken.json").path, contents: Data("{".utf8))
        XCTAssertThrowsError(try TrackedListStore.readSnapshot(at: folder.path("broken.json")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path("broken.json.corrupt-backup").path))
    }

    func testTheStandaloneListIsReadInPlaceAndLeftUntouched() throws {
        let folder = ScratchDirectory("standalone")
        let standalone = #"{"apps":[{"id":"x","name":"Private","source_type":"forgejo","source_url":"https://codeberg.org/o/p","username":"alice","access_token":"key123"}],"settings":{"github_token":"ghp_secret","gitlab_token":null},"self_entry_seeded":true}"#
        _ = FileManager.default.createFile(atPath: folder.path("apps.json").path, contents: Data(standalone.utf8))
        folder.setMode(0o644, "apps.json")

        XCTAssertTrue(StandaloneList.exists(at: folder.path("apps.json")))
        let data = try StandaloneList.read(at: folder.path("apps.json"))

        XCTAssertEqual(data.apps.first?.accessToken, "key123")
        XCTAssertEqual(data.settings.githubToken, "ghp_secret")
        XCTAssertEqual(try String(contentsOf: folder.path("apps.json"), encoding: .utf8), standalone)
        XCTAssertEqual(folder.mode("apps.json"), 0o644)
        XCTAssertFalse(StandaloneList.exists(at: folder.path("missing.json")))
    }
}
