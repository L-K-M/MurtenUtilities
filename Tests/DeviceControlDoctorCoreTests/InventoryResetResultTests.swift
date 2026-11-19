import XCTest
@testable import DoctorCore

final class InventoryResetResultTests: XCTestCase {
    private func entry(_ service: String, _ client: String, database: PermissionRecord.Database = .system,
                       kind: PermissionRecord.ClientKind = .bundleIdentifier) -> InventoryEntry {
        InventoryFixtures.entry(record: InventoryFixtures.record(service: service, client: client, clientKind: kind, database: database),
                                client: InventoryFixtures.client(), flags: [])
    }

    private func after(_ entries: [InventoryEntry], unreadable: PermissionRecord.Database? = nil) -> PermissionInventory {
        let sources = PermissionRecord.Database.allCases.map { database in
            DatabaseSource(database: database, reading: database == unreadable
                ? .needsFullDiskAccess
                : .read(entries.filter { $0.record.database == database }.map(\.record)))
        }
        let resolved = entries.filter { $0.record.database != unreadable }
            .map { ResolvedRecord(record: $0.record, client: $0.client, signature: .matches) }
        return PermissionInventory(sources: sources, resolved: resolved, readAt: InventoryFixtures.readAt)
    }

    func testEachEntryIsJudgedByTheFreshRead() {
        let removed = entry("kTCCServiceCamera", "com.a")
        let still = entry("kTCCServiceMicrophone", "com.a")
        let failed = entry("kTCCServiceCamera", "com.b")
        let unverified = entry("kTCCServiceCamera", "com.c", database: .user)
        let skipped = entry("kTCCServiceCamera", "/usr/local/bin/tool", kind: .path)

        let result = InventoryResetResult.assess(
            requested: [removed, still, failed, unverified], skipped: [skipped],
            commandFailures: [InventoryResetResult.commandKey(bundleIdentifier: "com.b", service: "Camera"): "exit 64"],
            after: after([still, failed], unreadable: .user))

        XCTAssertEqual(result.items.map(\.outcome), [.removed, .stillRecorded, .failed("exit 64"), .unverified, .skipped])
        XCTAssertEqual(result.summary, "Removed 1 entry. 1 entry is still recorded. A running app may have asked again, or your organization may manage it. tccutil did not reset 1 entry. 1 entry could not be checked afterwards. 1 entry can only be removed in System Settings.")
    }

    func testUncertainCommandsAreJudgedByTheFreshRead() {
        let gone = entry("kTCCServiceCamera", "com.a")
        let kept = entry("kTCCServiceMicrophone", "com.a")
        let uncertain = [
            InventoryResetResult.commandKey(bundleIdentifier: "com.a", service: "Camera"): "timed out",
            InventoryResetResult.commandKey(bundleIdentifier: "com.a", service: "Microphone"): "timed out",
        ]
        let result = InventoryResetResult.assess(requested: [gone, kept], skipped: [], commandFailures: [:],
                                                 uncertainCommands: uncertain, after: after([kept]))
        XCTAssertEqual(result.items.map(\.outcome), [.removed, .uncertain("timed out")])
        XCTAssertEqual(result.summary, "Removed 1 entry. tccutil's outcome was uncertain for 1 entry, and it is still recorded.")
    }

    /// A command tccutil reported failing is never shown as a removal,
    /// even when the entry is gone: something else may have removed it.
    func testAReportedFailureWinsOverAVanishedEntry() {
        let camera = entry("kTCCServiceCamera", "com.a")
        let result = InventoryResetResult.assess(
            requested: [camera], skipped: [],
            commandFailures: [InventoryResetResult.commandKey(bundleIdentifier: "com.a", service: "Camera"): "exit 64"],
            after: after([]))
        XCTAssertEqual(result.items.map(\.outcome), [.failed("exit 64")])
    }

    func testWithoutAFreshReadNothingCountsAsRemoved() {
        let camera = entry("kTCCServiceCamera", "com.a")
        let result = InventoryResetResult.assess(requested: [camera], skipped: [], commandFailures: [:], after: nil)
        XCTAssertEqual(result.items.map(\.outcome), [.unverified])
    }

    func testPluralsAndTheEmptyCase() {
        let entries = [entry("kTCCServiceCamera", "com.a"), entry("kTCCServiceMicrophone", "com.a")]
        let gone = InventoryResetResult.assess(requested: entries, skipped: [], commandFailures: [:], after: after([]))
        XCTAssertEqual(gone.summary, "Removed 2 entries.")

        let kept = InventoryResetResult.assess(requested: entries, skipped: [], commandFailures: [:], after: after(entries))
        XCTAssertTrue(kept.summary.hasPrefix("2 entries are still recorded."), kept.summary)
        XCTAssertTrue(kept.summary.contains("may manage them"), kept.summary)

        XCTAssertEqual(InventoryResetResult(items: []).summary, "Nothing was reset.")
    }
}
