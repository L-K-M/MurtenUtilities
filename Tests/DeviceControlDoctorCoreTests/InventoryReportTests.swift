import XCTest
@testable import DoctorCore

final class InventoryReportTests: XCTestCase {
    func testReportText() {
        let record = InventoryFixtures.record(service: "kTCCServiceSystemPolicyAllFiles",
                                              client: "com.foo",
                                              decision: .allowed,
                                              reason: 4,
                                              lastModified: InventoryFixtures.readAt)
        let client = ClientStatus(name: "Foo", presence: .installed(path: "/Applications/Foo.app"),
                                  isSystem: false, appIdentifier: "com.foo")
        let resolved = ResolvedRecord(record: record, client: client, signature: .matches)
        let source = DatabaseSource(database: .system, reading: .read([record]))
        let inventory = PermissionInventory(sources: [source], resolved: [resolved], readAt: InventoryFixtures.readAt)

        let text = InventoryReport.text(inventory, system: "macOS 27.0", timeZone: TimeZone(identifier: "UTC")!)

        XCTAssertTrue(text.hasPrefix("App Permission Checkup: privacy permissions\n"), text)
        XCTAssertTrue(text.contains("Read 2027-01-15 08:00 on macOS 27.0"), text)
        XCTAssertTrue(text.contains("For all users: read, 1 entry."), text)
        XCTAssertTrue(text.contains("Full Disk Access (kTCCServiceSystemPolicyAllFiles), 1"), text)
        XCTAssertTrue(text.contains("Allowed · Foo · com.foo · for all users · changed 2027-01-15 08:00 · reason System Set [High-risk]"), text)
        XCTAssertTrue(text.hasSuffix("\n"), text)
    }
}
