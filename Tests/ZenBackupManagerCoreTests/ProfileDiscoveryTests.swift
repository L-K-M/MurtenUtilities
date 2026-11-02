import XCTest
@testable import ZenBackupManager

final class ProfileDiscoveryTests: XCTestCase {
    func testINIParsesCRLFCommentsAndEqualsInPaths() {
        let parsed = ProfileDiscovery.parseINI(";comment\r\n[Profile0]\r\nName=Work\r\nPath=Profiles/a=b\r\nIsRelative=1\r\n")
        XCTAssertEqual(parsed["Profile0"]?["Path"], "Profiles/a=b")
        XCTAssertEqual(parsed["Profile0"]?["Name"], "Work")
    }

    func testInstallationDefaultWinsAndMissingProfilesAreSkipped() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["a", "b"] {
            let directory = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: directory.appendingPathComponent("prefs.js"))
        }
        try """
        [Profile0]
        Name=A
        Path=a
        IsRelative=1
        Default=1
        [Profile1]
        Name=B
        Path=b
        IsRelative=1
        [Install123]
        Default=b
        [Profile2]
        Name=Missing
        Path=missing
        IsRelative=1
        """.write(to: root.appendingPathComponent("profiles.ini"), atomically: true, encoding: .utf8)
        let profiles = try ProfileDiscovery.discover(root: root)
        XCTAssertEqual(profiles.map(\.name), ["B", "A"])
        XCTAssertTrue(profiles[0].isDefault)
        XCTAssertFalse(profiles[1].isDefault)
    }

    func testCatalogIncludesCorruptFilesAsDisabledRecords() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let backups = root.appendingPathComponent("zen-sessions-backup")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("prefs.js"))
        try Fixture.modern.write(to: backups.appendingPathComponent("zen-sessions-good.jsonlz4"))
        try Data("broken".utf8).write(to: backups.appendingPathComponent("zen-sessions-bad.jsonlz4"))
        let profile = ZenProfile(name: "Test", directory: root, isDefault: false)
        let records = try BackupCatalog.scan(profile: profile, safetyRoot: root.appendingPathComponent("safety"))
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.filter(\.canRestore).count, 1)
        XCTAssertEqual(records.filter { $0.problem != nil }.count, 1)
    }
}
