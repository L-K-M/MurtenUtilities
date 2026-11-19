import XCTest
@testable import DoctorCore

/// Reset plans, and the guidance for the entries a plan cannot cover.
final class InventoryResetPlanTests: XCTestCase {
    private func entry(service: String,
                       client: String = "com.foo",
                       database: PermissionRecord.Database = .system,
                       clientKind: PermissionRecord.ClientKind = .bundleIdentifier,
                       flags: InventoryEntry.Flags = []) -> InventoryEntry {
        let record = InventoryFixtures.record(service: service, client: client, clientKind: clientKind, database: database)
        let status = ClientStatus(name: "Foo",
                                  presence: clientKind == .path ? .installed(path: client) : .installed(path: "/Applications/Foo.app"),
                                  isSystem: flags.contains(.system),
                                  appIdentifier: clientKind == .bundleIdentifier ? client : nil)
        return InventoryFixtures.entry(record: record, client: status, flags: flags)
    }

    // MARK: - Plans

    func testServicesAndArguments() throws {
        let entries = [
            entry(service: "kTCCServiceCamera", client: "com.foo", database: .system),
            entry(service: "kTCCServiceMicrophone", client: "com.foo", database: .system),
            entry(service: "kTCCServiceCamera", client: "com.foo", database: .user),
        ]

        let plan = try InventoryResetPlan(entries: entries)

        XCTAssertEqual(plan.services, ["Camera", "Microphone"])
        XCTAssertEqual(plan.arguments, [["reset", "Camera", "com.foo"], ["reset", "Microphone", "com.foo"]])
    }

    func testInitRejectsNoEntriesAndMixedClients() {
        XCTAssertThrowsError(try InventoryResetPlan(entries: [])) { error in
            XCTAssertEqual(error as? InventoryResetError, .noEntries)
        }

        let mixed = [
            entry(service: "kTCCServiceCamera", client: "com.a"),
            entry(service: "kTCCServiceCamera", client: "com.b"),
        ]
        XCTAssertThrowsError(try InventoryResetPlan(entries: mixed)) { error in
            XCTAssertEqual(error as? InventoryResetError, .mixedClients)
        }
    }

    func testInitRejectsEntriesTccutilCannotReset() {
        let system = [entry(service: "kTCCServiceCamera", client: "com.apple.Foo", flags: [.system])]
        XCTAssertThrowsError(try InventoryResetPlan(entries: system)) { error in
            XCTAssertEqual(error as? InventoryResetError, .notResettable)
        }

        let managed = [entry(service: "kTCCServiceCamera", client: "com.foo", flags: [.managed])]
        XCTAssertThrowsError(try InventoryResetPlan(entries: managed)) { error in
            XCTAssertEqual(error as? InventoryResetError, .notResettable)
        }

        let path = [entry(service: "kTCCServiceCamera", client: "/Applications/Foo.app/Contents/MacOS/foo", clientKind: .path)]
        XCTAssertThrowsError(try InventoryResetPlan(entries: path)) { error in
            XCTAssertEqual(error as? InventoryResetError, .notResettable)
        }
    }

    func testServiceNameValidation() {
        XCTAssertFalse(InventoryResetPlan.isServiceName("All"))
        XCTAssertTrue(InventoryResetPlan.isServiceName("Camera"))
        XCTAssertFalse(InventoryResetPlan.isServiceName("Bad Name"))
        XCTAssertFalse(InventoryResetPlan.isServiceName(""))
    }

    func testUnknownServiceIsRejectedAndSkipped() {
        let unknown = entry(service: "kTCCServiceAll", client: "com.foo")

        XCTAssertThrowsError(try InventoryResetPlan(entries: [unknown])) { error in
            XCTAssertEqual(error as? InventoryResetError, .invalidService("kTCCServiceAll"))
        }

        let (_, skipped) = InventoryResetPlan.plans(for: [unknown])
        XCTAssertEqual(skipped, [unknown])
    }

    func testPlansGroupByClientAndSkipPathClients() {
        let entries = [
            entry(service: "kTCCServiceCamera", client: "com.a"),
            entry(service: "kTCCServiceMicrophone", client: "com.a"),
            entry(service: "kTCCServiceCamera", client: "com.b"),
            entry(service: "kTCCServiceCamera", client: "/Applications/Foo.app/Contents/MacOS/foo", clientKind: .path),
        ]

        let (plans, skipped) = InventoryResetPlan.plans(for: entries)

        XCTAssertEqual(plans.count, 2)
        XCTAssertEqual(plans[0].bundleIdentifier, "com.a")
        XCTAssertEqual(plans[0].services, ["Camera", "Microphone"])
        XCTAssertEqual(plans[1].bundleIdentifier, "com.b")
        XCTAssertEqual(plans[1].services, ["Camera"])
        XCTAssertEqual(skipped, [entries[3]])
    }

    // MARK: - Guidance

    func testGuidanceForSystemAndManagedEntries() {
        let system = entry(service: "kTCCServiceCamera", client: "com.apple.Foo", flags: [.system])
        XCTAssertTrue(InventoryGuidance.steps(for: system).contains("part of macOS"))

        let managed = entry(service: "kTCCServiceCamera", client: "com.foo", flags: [.managed])
        XCTAssertTrue(InventoryGuidance.steps(for: managed).contains("organization"))
    }

    func testGuidanceForRemovableAndToggleOnlyLists() {
        let allFiles = entry(service: "kTCCServiceSystemPolicyAllFiles", client: "com.foo")
        let allFilesSteps = InventoryGuidance.steps(for: allFiles)
        XCTAssertTrue(allFilesSteps.contains("Full Disk Access"), allFilesSteps)
        XCTAssertTrue(allFilesSteps.contains("“Foo”"), allFilesSteps)
        XCTAssertTrue(allFilesSteps.contains("remove (−)"), allFilesSteps)

        let camera = entry(service: "kTCCServiceCamera", client: "com.foo")
        let cameraSteps = InventoryGuidance.steps(for: camera)
        XCTAssertTrue(cameraSteps.contains("turn off"), cameraSteps)
        XCTAssertTrue(cameraSteps.contains("Camera"), cameraSteps)
    }

    func testGuidanceForAWildService() {
        let unknown = entry(service: "kTCCServiceFooBar", client: "com.foo")

        XCTAssertTrue(InventoryGuidance.steps(for: unknown).contains("has no list"))
    }
}
