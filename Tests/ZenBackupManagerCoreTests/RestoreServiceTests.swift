import XCTest
@testable import ZenBackupManager

final class RestoreServiceTests: XCTestCase {
    var root: URL!
    var profile: ZenProfile!
    var safetyRoot: URL { root.appendingPathComponent("safety") }
    var modernTarget: URL { profile.directory.appendingPathComponent("zen-sessions.jsonlz4") }
    var legacyTarget: URL { profile.directory.appendingPathComponent("sessionstore.jsonlz4") }
    var service: RestoreService { RestoreService(safetyRoot: safetyRoot, isZenRunning: { false }) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent("profile")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("// synthetic profile".utf8).write(to: directory.appendingPathComponent("prefs.js"))
        profile = ZenProfile(name: "Test", directory: directory, isDefault: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func backup(_ data: Data = Fixture.modern) throws -> BackupRecord {
        let file = root.appendingPathComponent(UUID().uuidString + ".jsonlz4")
        try data.write(to: file)
        return BackupRecord(file: file, modifiedAt: Date(), bytes: data.count, kind: .automatic,
            preview: try SessionPreview.parse(data), digest: SessionFiles.digest(data), problem: nil)
    }

    func testRestorePreservesOriginalBytesAndUndoRestoresThem() throws {
        let original = Fixture.compressed("{\"tabs\":[],\"spaces\":[]}")
        try original.write(to: modernTarget)
        try Fixture.legacy.write(to: legacyTarget)
        let archive = try service.restore(backup(), to: profile)
        XCTAssertEqual(try Data(contentsOf: modernTarget), Fixture.modern)
        XCTAssertEqual(try Data(contentsOf: legacyTarget), Fixture.legacy)
        XCTAssertEqual(try archive.verifiedContents(profile: profile)["zen-sessions.jsonlz4"], original)
        _ = try service.undo(archive, profile: profile)
        XCTAssertEqual(try Data(contentsOf: modernTarget), original)
        XCTAssertEqual(try Data(contentsOf: legacyTarget), Fixture.legacy)
        XCTAssertEqual(try SafetyArchive.list(root: safetyRoot, profile: profile).count, 2)
    }

    func testUndoRestoresAbsenceOfModernFile() throws {
        try Fixture.legacy.write(to: legacyTarget)
        let archive = try service.restore(backup(), to: profile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: modernTarget.path))
        _ = try service.undo(archive, profile: profile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: modernTarget.path))
        XCTAssertEqual(try Data(contentsOf: legacyTarget), Fixture.legacy)
    }

    func testLegacyRestoreUsesMigrationAndUndoPreservesModern() throws {
        try Fixture.modern.write(to: modernTarget)
        let archive = try service.restore(backup(Fixture.legacy), to: profile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: modernTarget.path))
        XCTAssertEqual(try Data(contentsOf: legacyTarget), Fixture.legacy)
        _ = try service.undo(archive, profile: profile)
        XCTAssertEqual(try Data(contentsOf: modernTarget), Fixture.modern)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyTarget.path))
    }

    func testRunningBrowserPreventsAnySessionWrite() throws {
        try Fixture.modern.write(to: modernTarget)
        let running = RestoreService(safetyRoot: safetyRoot, isZenRunning: { true })
        XCTAssertThrowsError(try running.restore(backup(), to: profile))
        XCTAssertFalse(FileManager.default.fileExists(atPath: safetyRoot.path))
        XCTAssertEqual(try Data(contentsOf: modernTarget), Fixture.modern)
    }

    func testChangedSourceIsRejectedBeforeCreatingSafetyCopy() throws {
        let record = try backup()
        try Fixture.legacy.write(to: record.file)
        XCTAssertThrowsError(try service.restore(record, to: profile))
        XCTAssertFalse(FileManager.default.fileExists(atPath: safetyRoot.path))
    }

    func testSymlinkDestinationIsRejectedWithoutTouchingTarget() throws {
        let outside = root.appendingPathComponent("important")
        try Data("untouched".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: modernTarget, withDestinationURL: outside)
        XCTAssertThrowsError(try service.restore(backup(), to: profile))
        XCTAssertEqual(try String(contentsOf: outside), "untouched")
    }

    func testWriteFailureRollsBackBothFiles() throws {
        try Fixture.modern.write(to: modernTarget)
        try Fixture.legacy.write(to: legacyTarget)
        let failing = RestoreService(safetyRoot: safetyRoot, isZenRunning: { false }, write: { data, file in
            try SessionFiles.write(data, to: file)
            throw BackupError.invalid("Simulated failure after replacement")
        })
        XCTAssertThrowsError(try failing.restore(backup(Fixture.legacy), to: profile))
        XCTAssertEqual(try Data(contentsOf: modernTarget), Fixture.modern)
        XCTAssertEqual(try Data(contentsOf: legacyTarget), Fixture.legacy)
    }

    func testTamperedSafetyCopyCannotUndo() throws {
        try Fixture.modern.write(to: modernTarget)
        let archive = try service.restore(backup(Fixture.legacy), to: profile)
        try Fixture.legacy.write(to: archive.directory.appendingPathComponent("zen-sessions.jsonlz4"))
        XCTAssertThrowsError(try service.undo(archive, profile: profile))
        XCTAssertEqual(try Data(contentsOf: legacyTarget), Fixture.legacy)
    }

    func testSafetyCopyCannotRestoreToAnotherProfile() throws {
        let archive = try service.restore(backup(), to: profile)
        let other = ZenProfile(name: "Other", directory: root.appendingPathComponent("other"), isDefault: false)
        XCTAssertThrowsError(try archive.verifiedContents(profile: other))
    }

    func testSafetyCopyPermissionsArePrivate() throws {
        try Fixture.modern.write(to: modernTarget)
        let archive = try service.restore(backup(), to: profile)
        let attributes = try FileManager.default.attributesOfItem(atPath: archive.directory.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: modernTarget.path)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testEmptyCorruptCurrentFileIsPreservedForUndo() throws {
        try Data().write(to: modernTarget)
        let archive = try service.restore(backup(), to: profile)
        XCTAssertEqual(try archive.verifiedContents(profile: profile)["zen-sessions.jsonlz4"], Data())
        _ = try service.undo(archive, profile: profile)
        XCTAssertEqual(try Data(contentsOf: modernTarget), Data())
    }

    func testProfileLockBlocksAnotherProcess() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", "import fcntl,sys; f=open(sys.argv[1], 'a'); fcntl.lockf(f,fcntl.LOCK_EX); print('locked',flush=True); sys.stdin.read()", profile.directory.appendingPathComponent(".parentlock").path]
        let input = Pipe(), output = Pipe()
        process.standardInput = input; process.standardOutput = output
        try process.run()
        defer { try? input.fileHandleForWriting.close(); process.waitUntilExit() }
        XCTAssertEqual(String(data: output.fileHandleForReading.availableData, encoding: .utf8), "locked\n")
        XCTAssertThrowsError(try service.restore(backup(), to: profile))
        XCTAssertFalse(FileManager.default.fileExists(atPath: safetyRoot.path))
    }

}
