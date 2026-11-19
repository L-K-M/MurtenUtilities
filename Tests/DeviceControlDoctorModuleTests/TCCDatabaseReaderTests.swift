import Foundation
import SQLite3
import XCTest
import DoctorCore
@testable import DeviceControlDoctorModule

/// The reader against fixture databases built with macOS 27.0.1's own
/// schema (tccd's `CREATE TABLE` statements). Never opens the live ones.
final class TCCDatabaseReaderTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("TCCDatabaseReaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        let locked = folder.appendingPathComponent("locked.db").path
        if FileManager.default.fileExists(atPath: locked) {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: locked)
        }
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Fixtures

    static let accessSchema = """
        CREATE TABLE access (    service        TEXT        NOT NULL,     client         TEXT        NOT NULL,     client_type    INTEGER     NOT NULL,     auth_value     INTEGER     NOT NULL,     auth_reason    INTEGER     NOT NULL,     auth_version   INTEGER     NOT NULL,     csreq          BLOB,     policy_id      INTEGER,     indirect_object_identifier_type    INTEGER,     indirect_object_identifier         TEXT NOT NULL DEFAULT 'UNUSED',     indirect_object_code_identity      BLOB,     flags          INTEGER,     last_modified  INTEGER     NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)),     pid            INTEGER,     pid_version    INTEGER,     boot_uuid      TEXT NOT NULL DEFAULT 'UNUSED',     last_reminded  INTEGER     NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)),     one_time_reprompt_eligible INTEGER,     reminder_count INTEGER NOT NULL DEFAULT 0,     PRIMARY KEY (service, client, client_type, indirect_object_identifier));
        """

    static let managedSchema = """
        CREATE TABLE managed_overrides (    service        TEXT        NOT NULL,     client         TEXT        NOT NULL,     client_type    INTEGER     NOT NULL,     auth_value     INTEGER     NOT NULL DEFAULT 1,     auth_reason    INTEGER     NOT NULL,     auth_version   INTEGER     NOT NULL,     csreq          BLOB,     policy_id      INTEGER,     indirect_object_identifier_type    INTEGER,     indirect_object_identifier         TEXT NOT NULL DEFAULT 'UNUSED',     indirect_object_code_identity      BLOB,     flags          INTEGER     NOT NULL DEFAULT 0,     last_modified  INTEGER     NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)),     one_time_reprompt_eligible INTEGER,     admin_auth_value    INTEGER NOT NULL,    PRIMARY KEY (service, client, client_type, indirect_object_identifier));
        """

    private func makeDatabase(_ name: String, statements: [String]) throws -> String {
        let path = folder.appendingPathComponent(name).path
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        for statement in statements {
            var error: UnsafeMutablePointer<CChar>?
            let code = sqlite3_exec(handle, statement, nil, nil, &error)
            let message = error.map { String(cString: $0) } ?? ""
            sqlite3_free(error)
            XCTAssertEqual(code, SQLITE_OK, message)
        }
        return path
    }

    private func systemDatabase() throws -> String {
        try makeDatabase("system.db", statements: [
            Self.accessSchema,
            Self.managedSchema,
            // A bundle client with a code requirement, allowed by the user in Settings.
            "INSERT INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, last_modified) VALUES ('kTCCServiceSystemPolicyAllFiles', 'com.example.Backup', 0, 2, 4, 1, X'FADE0C00', 1800000000)",
            // A path client, denied.
            "INSERT INTO access (service, client, client_type, auth_value, auth_reason, auth_version, last_modified) VALUES ('kTCCServiceAccessibility', '/usr/local/bin/helper', 1, 0, 2, 1, 1700000000)",
            // Automation of Finder.
            "INSERT INTO access (service, client, client_type, auth_value, auth_reason, auth_version, indirect_object_identifier_type, indirect_object_identifier) VALUES ('kTCCServiceAppleEvents', 'com.example.Scripter', 0, 2, 3, 1, 0, 'com.apple.finder')",
            // A client type this version does not know: skipped, not guessed.
            "INSERT INTO access (service, client, client_type, auth_value, auth_reason, auth_version) VALUES ('kTCCServiceCamera', 'odd', 7, 2, 2, 1)",
            // Device management overrides the Backup grant and adds one of its own.
            "INSERT INTO managed_overrides (service, client, client_type, auth_value, auth_reason, auth_version, admin_auth_value) VALUES ('kTCCServiceSystemPolicyAllFiles', 'com.example.Backup', 0, 0, 6, 1, 2)",
            "INSERT INTO managed_overrides (service, client, client_type, auth_value, auth_reason, auth_version, admin_auth_value) VALUES ('kTCCServiceScreenCapture', 'com.example.Recorder', 0, 2, 6, 1, 2)",
        ])
    }

    // MARK: - Reading

    func testReadsEveryRowWithItsFieldsAndFoldsInManagedOverrides() throws {
        let reader = TCCDatabaseReader(systemPath: try systemDatabase(), userPath: folder.appendingPathComponent("none.db").path)
        guard case .read(let records) = reader.read(.system) else { return XCTFail("expected a read") }

        XCTAssertEqual(records.count, 4, "the unknown client type is skipped")
        let backup = try XCTUnwrap(records.first { $0.client == "com.example.Backup" })
        XCTAssertEqual(backup.database, .system)
        XCTAssertEqual(backup.service, "kTCCServiceSystemPolicyAllFiles")
        XCTAssertEqual(backup.clientKind, .bundleIdentifier)
        XCTAssertEqual(backup.decision, .denied, "the managed override's decision applies")
        XCTAssertTrue(backup.isManaged)
        XCTAssertEqual(backup.reason, 4)
        XCTAssertEqual(backup.requirement, Data([0xFA, 0xDE, 0x0C, 0x00]))
        XCTAssertEqual(backup.lastModified, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertNil(backup.target)

        let helper = try XCTUnwrap(records.first { $0.client == "/usr/local/bin/helper" })
        XCTAssertEqual(helper.clientKind, .path)
        XCTAssertEqual(helper.decision, .denied)
        XCTAssertFalse(helper.isManaged)
        XCTAssertNil(helper.requirement)

        let scripter = try XCTUnwrap(records.first { $0.client == "com.example.Scripter" })
        XCTAssertEqual(scripter.target, "com.apple.finder")
        XCTAssertEqual(scripter.decision, .allowed)

        let recorder = try XCTUnwrap(records.first { $0.client == "com.example.Recorder" })
        XCTAssertTrue(recorder.isManaged)
        XCTAssertEqual(recorder.service, "kTCCServiceScreenCapture")
    }

    func testReadsADatabaseWithoutManagedOverrides() throws {
        let path = try makeDatabase("plain.db", statements: [
            Self.accessSchema,
            "INSERT INTO access (service, client, client_type, auth_value, auth_reason, auth_version) VALUES ('kTCCServiceCamera', 'com.example.Cam', 0, 2, 2, 1)",
        ])
        let reader = TCCDatabaseReader(systemPath: "/nonexistent", userPath: path)
        guard case .read(let records) = reader.read(.user) else { return XCTFail("expected a read") }
        XCTAssertEqual(records.map(\.client), ["com.example.Cam"])
        XCTAssertEqual(records.first?.database, .user)
    }

    /// tccd's schema forbids NULL here; a database that breaks it gets its
    /// odd rows skipped rather than read as Denied bundle clients.
    func testRowsWithoutAClientTypeOrDecisionAreSkipped() throws {
        let path = try makeDatabase("lenient.db", statements: [
            "CREATE TABLE access (service TEXT, client TEXT, client_type INTEGER, auth_value INTEGER, auth_reason INTEGER, auth_version INTEGER, csreq BLOB, indirect_object_identifier TEXT, last_modified INTEGER)",
            "INSERT INTO access VALUES ('kTCCServiceCamera', 'com.example.NoValue', 0, NULL, 2, 1, NULL, 'UNUSED', 1)",
            "INSERT INTO access VALUES ('kTCCServiceCamera', 'com.example.NoType', NULL, 2, 2, 1, NULL, 'UNUSED', 1)",
            "INSERT INTO access VALUES ('kTCCServiceCamera', 'com.example.Fine', 0, 2, 2, 1, NULL, NULL, NULL)",
        ])
        guard case .read(let records) = TCCDatabaseReader(systemPath: path, userPath: "/nonexistent").read(.system) else {
            return XCTFail("expected a read")
        }
        XCTAssertEqual(records.map(\.client), ["com.example.Fine"])
        XCTAssertNil(records.first?.target)
        XCTAssertNil(records.first?.lastModified)
    }

    func testNeverChangesTheDatabase() throws {
        let path = try systemDatabase()
        let before = try Data(contentsOf: URL(fileURLWithPath: path))
        let modified = try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date

        _ = TCCDatabaseReader(systemPath: path, userPath: "/nonexistent").read(.system)

        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), before)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date, modified)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("system.db-") }
        XCTAssertEqual(leftovers, [], "no journal or WAL files are created")
    }

    // MARK: - Failures

    func testAMissingDatabaseIsMissingNotEmpty() {
        let reader = TCCDatabaseReader(systemPath: folder.appendingPathComponent("absent.db").path,
                                       userPath: folder.appendingPathComponent("absent/TCC.db").path)
        guard case .missing = reader.read(.system) else { return XCTFail("expected missing") }
        guard case .missing = reader.read(.user) else { return XCTFail("expected missing") }
    }

    func testUserDatabaseLivesInTheHomeLibrary() {
        XCTAssertEqual(TCCDatabaseReader(home: "/Users/someone").userPath,
                       "/Users/someone/Library/Application Support/com.apple.TCC/TCC.db")
        XCTAssertEqual(TCCDatabaseReader().systemPath, "/Library/Application Support/com.apple.TCC/TCC.db")
    }

    func testAFileThatIsNotADatabaseFails() throws {
        let path = folder.appendingPathComponent("garbage.db").path
        try Data(repeating: 0x41, count: 4096).write(to: URL(fileURLWithPath: path))
        guard case .failed(let detail) = TCCDatabaseReader(systemPath: path, userPath: "/nonexistent").read(.system) else {
            return XCTFail("expected a failure")
        }
        XCTAssertFalse(detail.isEmpty)
    }

    func testADatabaseWithoutTheAccessTableFails() throws {
        let path = try makeDatabase("empty.db", statements: ["CREATE TABLE admin (key TEXT PRIMARY KEY NOT NULL, value INTEGER NOT NULL)"])
        guard case .failed(let detail) = TCCDatabaseReader(systemPath: path, userPath: "/nonexistent").read(.system) else {
            return XCTFail("expected a failure")
        }
        XCTAssertTrue(detail.contains("access"), detail)
    }

    // MARK: - Live

    /// Opt-in (`MURTEN_LIVE_TCC=1`): reads this Mac's real databases, which
    /// needs Full Disk Access for the test runner. Read-only; checks that the
    /// live schema reads and every row classifies.
    func testLiveDatabasesReadWithoutFailure() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MURTEN_LIVE_TCC"] == "1", "set MURTEN_LIVE_TCC=1 to read the live databases")
        let reader = TCCDatabaseReader()
        let sources = PermissionRecord.Database.allCases.map { DatabaseSource(database: $0, reading: reader.read($0)) }
        for source in sources {
            if case .failed(let detail) = source.reading { XCTFail("\(source.database): \(detail)") }
        }
        try XCTSkipIf(sources.contains { if case .needsFullDiskAccess = $0.reading { return true }; return false },
                      "the test runner has no Full Disk Access")
        let resolved = await ClientResolver().resolve(sources.flatMap(\.reading.records))
        let inventory = PermissionInventory(sources: sources, resolved: resolved, readAt: Date())
        // Counts only: the entries name this Mac's apps.
        print(InventoryReport.text(inventory, system: ProcessInfo.processInfo.operatingSystemVersionString)
            .split(separator: "\n").filter { !$0.hasPrefix("  ") }.joined(separator: "\n"))
        XCTAssertEqual(inventory.entries.count, sources.reduce(0) { $0 + $1.reading.records.count })
    }

    /// File permissions are not the privacy system: Full Disk Access would
    /// not help, so it is not asked for.
    func testUnreadableFilePermissionsAreAFailureNotAFullDiskAccessRequest() throws {
        let path = try makeDatabase("locked.db", statements: [Self.accessSchema])
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path)
        try XCTSkipIf(FileManager.default.isReadableFile(atPath: path), "running with privileges that ignore file permissions")
        switch TCCDatabaseReader(systemPath: path, userPath: "/nonexistent").read(.system) {
        case .failed: break
        case let other: XCTFail("expected a failure, got \(other)")
        }
    }
}
