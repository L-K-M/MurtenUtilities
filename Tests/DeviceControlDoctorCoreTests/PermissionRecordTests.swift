import XCTest
@testable import DoctorCore

final class PermissionRecordTests: XCTestCase {
    // MARK: - Decision

    func testDecisionMapsAuthValues() {
        XCTAssertEqual(PermissionRecord.Decision(authValue: 0), .denied)
        XCTAssertEqual(PermissionRecord.Decision(authValue: 1), .unknown)
        XCTAssertEqual(PermissionRecord.Decision(authValue: 2), .allowed)
        XCTAssertEqual(PermissionRecord.Decision(authValue: 3), .limited)
        XCTAssertEqual(PermissionRecord.Decision(authValue: 7), .other(7))
    }

    func testGrantsAccessOnlyForAllowedAndLimited() {
        XCTAssertFalse(PermissionRecord.Decision(authValue: 0).grantsAccess)
        XCTAssertFalse(PermissionRecord.Decision(authValue: 1).grantsAccess)
        XCTAssertTrue(PermissionRecord.Decision(authValue: 2).grantsAccess)
        XCTAssertTrue(PermissionRecord.Decision(authValue: 3).grantsAccess)
        XCTAssertFalse(PermissionRecord.Decision(authValue: 7).grantsAccess)
    }

    // MARK: - Client kind

    func testClientKindMapsClientType() {
        XCTAssertEqual(PermissionRecord.ClientKind(clientType: 0), .bundleIdentifier)
        XCTAssertEqual(PermissionRecord.ClientKind(clientType: 1), .path)
        XCTAssertNil(PermissionRecord.ClientKind(clientType: 2))
    }

    // MARK: - Managed rows

    func testMdmReasonMarksTheRecordManaged() {
        let mdm = InventoryFixtures.record(reason: 6)

        XCTAssertTrue(mdm.isManaged)
    }

    func testOtherReasonDoesNotMarkTheRecordManaged() {
        let systemSet = InventoryFixtures.record(reason: 4, isManaged: false)

        XCTAssertFalse(systemSet.isManaged)
    }

    func testReasonTitles() {
        XCTAssertEqual(InventoryFixtures.record(reason: 4).reasonTitle, "System Set")
        XCTAssertEqual(InventoryFixtures.record(reason: 6).reasonTitle, "MDM Policy")
        XCTAssertNil(InventoryFixtures.record(reason: 99).reasonTitle)
    }

    // MARK: - Key

    func testKeyDistinguishesDatabaseAndTarget() {
        let base = InventoryFixtures.record()
        let otherDatabase = InventoryFixtures.record(database: .user)
        let withTarget = InventoryFixtures.record(target: "com.bar")

        XCTAssertNotEqual(base.key, otherDatabase.key)
        XCTAssertNotEqual(base.key, withTarget.key)
    }

    // MARK: - Merging

    func testMergingFoldsManagedOverridesAndKeepsOrder() {
        let accessA = InventoryFixtures.record(service: "kTCCServiceCamera", client: "com.a", decision: .allowed)
        let accessB = InventoryFixtures.record(service: "kTCCServiceMicrophone", client: "com.b", decision: .denied)
        let managedA = InventoryFixtures.record(service: "kTCCServiceCamera", client: "com.a", decision: .denied)
        let managedC = InventoryFixtures.record(service: "kTCCServiceScreenCapture", client: "com.c", decision: .allowed)

        let merged = PermissionRecord.merging(access: [accessA, accessB], managed: [managedA, managedC])

        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged.map(\.client), ["com.a", "com.b", "com.c"])
        XCTAssertEqual(merged[0].decision, .denied)
        XCTAssertTrue(merged[0].isManaged)
        XCTAssertEqual(merged[1].decision, .denied)
        XCTAssertFalse(merged[1].isManaged)
        XCTAssertEqual(merged[2].decision, .allowed)
        XCTAssertTrue(merged[2].isManaged)
        XCTAssertTrue(merged.allSatisfy { $0.database == .system && $0.clientKind == .bundleIdentifier })
    }

    /// tccd can store an override with only `admin_auth_value`, leaving
    /// `auth_value` at 1: it marks the entry managed but decides nothing.
    func testAnOverrideWithoutADecisionKeepsTheRecordedOne() {
        let access = InventoryFixtures.record(service: "kTCCServiceCamera", client: "com.a", decision: .allowed)
        let adminOnly = InventoryFixtures.record(service: "kTCCServiceCamera", client: "com.a", decision: .unknown)
        let standalone = InventoryFixtures.record(service: "kTCCServiceMicrophone", client: "com.b", decision: .unknown)

        let merged = PermissionRecord.merging(access: [access], managed: [adminOnly, standalone])

        XCTAssertEqual(merged.map(\.client), ["com.a"], "an override that decides nothing is not an entry of its own")
        XCTAssertEqual(merged[0].decision, .allowed)
        XCTAssertTrue(merged[0].isManaged)
    }

    // MARK: - DatabaseReading

    func testOpenFailureMapsErrnos() {
        assertReading(DatabaseReading.forOpenFailure(errno: ENOENT, detail: "gone"), is: .missing)
        assertReading(DatabaseReading.forOpenFailure(errno: EPERM, detail: "refused"), is: .needsFullDiskAccess)
        assertReading(DatabaseReading.forOpenFailure(errno: EACCES, detail: "nope"), is: .failed("nope"))
    }

    private func assertReading(_ reading: DatabaseReading, is expected: DatabaseReading) {
        switch (reading, expected) {
        case (.missing, .missing), (.needsFullDiskAccess, .needsFullDiskAccess):
            break
        case (.failed(let detail), .failed(let expectedDetail)):
            XCTAssertEqual(detail, expectedDetail)
        default:
            XCTFail("got \(reading), expected \(expected)")
        }
    }

    // MARK: - DatabaseSource

    func testUserDatabaseMissingSummary() {
        let source = DatabaseSource(database: .user, reading: .missing)

        XCTAssertTrue(source.summary.contains("not readable on this version of macOS"), source.summary)
    }

    func testSystemDatabaseReadSummary() {
        let first = InventoryFixtures.record()
        let second = InventoryFixtures.record(client: "com.bar")

        XCTAssertEqual(DatabaseSource(database: .system, reading: .read([first, second])).summary,
                       "For all users: read, 2 entries.")
        XCTAssertEqual(DatabaseSource(database: .system, reading: .read([first])).summary,
                       "For all users: read, 1 entry.")
    }
}
