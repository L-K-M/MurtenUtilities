import XCTest
@testable import DoctorCore

final class PermissionInventoryTests: XCTestCase {
    private func entry(for resolved: ResolvedRecord) throws -> InventoryEntry {
        try XCTUnwrap(InventoryFixtures.inventory([resolved]).entries.first)
    }

    // MARK: - Risk

    func testHighRiskFlag() throws {
        let allowed = try entry(for: InventoryFixtures.resolved(
            InventoryFixtures.record(service: "kTCCServiceSystemPolicyAllFiles", decision: .allowed)))
        XCTAssertEqual(allowed.flags, [.highRisk])

        let denied = try entry(for: InventoryFixtures.resolved(
            InventoryFixtures.record(service: "kTCCServiceSystemPolicyAllFiles", decision: .denied)))
        XCTAssertEqual(denied.flags, [])

        let limited = try entry(for: InventoryFixtures.resolved(
            InventoryFixtures.record(service: "kTCCServiceAccessibility", decision: .limited)))
        XCTAssertTrue(limited.flags.contains(.highRisk))

        let camera = try entry(for: InventoryFixtures.resolved(
            InventoryFixtures.record(service: "kTCCServiceCamera", decision: .allowed)))
        XCTAssertFalse(camera.flags.contains(.highRisk))
    }

    // MARK: - Leftovers and offline

    func testLeftoverAndOfflineFlags() throws {
        let missing = try entry(for: InventoryFixtures.resolved(
            InventoryFixtures.record(),
            client: ClientStatus(name: "Gone", presence: .missing, isSystem: false)))
        XCTAssertTrue(missing.flags.contains(.leftover))

        let trashed = try entry(for: InventoryFixtures.resolved(
            InventoryFixtures.record(),
            client: ClientStatus(name: "Trashed", presence: .inTrash(path: "/Users/u/.Trash/Trashed.app"), isSystem: false)))
        XCTAssertTrue(trashed.flags.contains(.leftover))

        let offline = try entry(for: InventoryFixtures.resolved(
            InventoryFixtures.record(),
            client: ClientStatus(name: "Offline", presence: .offline(path: "/Volumes/Ext/Apps/Offline.app"), isSystem: false)))
        XCTAssertTrue(offline.flags.contains(.offline))
        XCTAssertFalse(offline.flags.contains(.leftover))
    }

    // MARK: - System clients

    func testSystemClientsAreNeverLeftoverBrokenOrLookAlike() throws {
        let system = try entry(for: InventoryFixtures.resolved(
            InventoryFixtures.record(),
            client: ClientStatus(name: "system", presence: .missing, isSystem: true),
            signature: .changed))

        XCTAssertTrue(system.flags.contains(.system))
        XCTAssertFalse(system.flags.contains(.leftover))
        XCTAssertFalse(system.flags.contains(.broken))
        XCTAssertFalse(system.flags.contains(.lookAlike))
    }

    // MARK: - Signature

    func testBrokenFlag() throws {
        let changed = try entry(for: InventoryFixtures.resolved(InventoryFixtures.record(), signature: .changed))
        XCTAssertTrue(changed.flags.contains(.broken))

        let notChecked = try entry(for: InventoryFixtures.resolved(InventoryFixtures.record(), signature: .notChecked("x")))
        XCTAssertFalse(notChecked.flags.contains(.broken))
    }

    // MARK: - Managed

    func testManagedFlagDisablesReset() throws {
        let managed = try entry(for: InventoryFixtures.resolved(InventoryFixtures.record(isManaged: true)))

        XCTAssertTrue(managed.flags.contains(.managed))
        XCTAssertFalse(managed.canReset)
    }

    // MARK: - Look-alikes

    func testLookAlikesShareADisplayName() throws {
        let zoom = InventoryFixtures.resolved(
            InventoryFixtures.record(client: "com.zoom.a"),
            client: ClientStatus(name: "Zoom", presence: .installed(path: "/Applications/Zoom.app"),
                                 isSystem: false, appIdentifier: "com.zoom.a"))
        let evil = InventoryFixtures.resolved(
            InventoryFixtures.record(client: "com.evil.zoom"),
            client: ClientStatus(name: "Zoom", presence: .installed(path: "/Applications/EvilZoom.app"),
                                 isSystem: false, appIdentifier: "com.evil.zoom"))

        let entries = InventoryFixtures.inventory([zoom, evil]).entries
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.flags.contains(.lookAlike) })
    }

    func testLookAlikeNamesAreCaseInsensitive() throws {
        let lower = InventoryFixtures.resolved(
            InventoryFixtures.record(client: "com.zoom.a"),
            client: ClientStatus(name: "zoom", presence: .installed(path: "/Applications/zoom.app"),
                                 isSystem: false, appIdentifier: "com.zoom.a"))
        let upper = InventoryFixtures.resolved(
            InventoryFixtures.record(client: "com.evil.zoom"),
            client: ClientStatus(name: "Zoom", presence: .installed(path: "/Applications/EvilZoom.app"),
                                 isSystem: false, appIdentifier: "com.evil.zoom"))

        let entries = InventoryFixtures.inventory([lower, upper]).entries
        XCTAssertTrue(entries.allSatisfy { $0.flags.contains(.lookAlike) })
    }

    func testSameAppByBundleAndPathIsNotALookAlike() throws {
        let bundle = InventoryFixtures.resolved(
            InventoryFixtures.record(client: "com.foo"),
            client: ClientStatus(name: "Foo", presence: .installed(path: "/Applications/Foo.app"),
                                 isSystem: false, appIdentifier: "com.foo"))
        let pathRecord = InventoryFixtures.record(client: "/Applications/Foo.app/Contents/MacOS/foo", clientKind: .path)
        let pathClient = InventoryFixtures.resolved(
            pathRecord,
            client: ClientStatus(name: "Foo", presence: .installed(path: "/Applications/Foo.app/Contents/MacOS/foo"),
                                 isSystem: false, appIdentifier: "com.foo"))

        let entries = InventoryFixtures.inventory([bundle, pathClient]).entries
        XCTAssertFalse(entries.contains { $0.flags.contains(.lookAlike) })
    }

    func testMissingClientNamedAfterItsIdentifierIsNotALookAlike() throws {
        let missing = InventoryFixtures.resolved(
            InventoryFixtures.record(client: "com.foo"),
            client: ClientStatus(name: "com.foo", presence: .missing, isSystem: false, appIdentifier: "com.foo"))
        let other = InventoryFixtures.resolved(
            InventoryFixtures.record(client: "com.other"),
            client: ClientStatus(name: "com.foo", presence: .installed(path: "/Applications/Foo.app"),
                                 isSystem: false, appIdentifier: "com.other"))

        let entries = InventoryFixtures.inventory([missing, other]).entries
        let missingEntry = try XCTUnwrap(entries.first { $0.record.client == "com.foo" })
        XCTAssertFalse(missingEntry.flags.contains(.lookAlike))
        let installedEntry = try XCTUnwrap(entries.first { $0.record.client == "com.other" })
        XCTAssertFalse(installedEntry.flags.contains(.lookAlike))
    }

    // MARK: - Automation targets

    func testMissingAutomationTarget() throws {
        let record = InventoryFixtures.record(service: "kTCCServiceAppleEvents", target: "com.gone.app")
        let missingTarget = try entry(for: InventoryFixtures.resolved(
            record,
            target: ClientStatus(name: "com.gone.app", presence: .missing, isSystem: false)))
        XCTAssertTrue(missingTarget.flags.contains(.missingTarget))

        let systemTarget = try entry(for: InventoryFixtures.resolved(
            record,
            target: ClientStatus(name: "com.gone.app", presence: .missing, isSystem: true)))
        XCTAssertFalse(systemTarget.flags.contains(.missingTarget))
    }

    // MARK: - Reset

    func testFlagLabelsMarkWarnings() {
        let entry = InventoryFixtures.entry(record: InventoryFixtures.record(), client: InventoryFixtures.client(),
                                            flags: [.leftover, .highRisk, .managed, .system])
        XCTAssertEqual(entry.flagLabels.map(\.title), ["Leftover", "High-risk", "Managed", "macOS"])
        XCTAssertEqual(entry.flagLabels.map(\.isWarning), [true, true, false, false])
        XCTAssertEqual(entry.flagTitles, entry.flagLabels.map(\.title))
    }

    func testCanReset() throws {
        let bundle = try entry(for: InventoryFixtures.resolved(InventoryFixtures.record(client: "com.foo")))
        XCTAssertTrue(bundle.canReset)

        let pathRecord = InventoryFixtures.record(client: "/Applications/Foo.app/Contents/MacOS/foo", clientKind: .path)
        let pathEntry = try entry(for: InventoryFixtures.resolved(
            pathRecord,
            client: ClientStatus(name: "foo", presence: .installed(path: "/Applications/Foo.app/Contents/MacOS/foo"), isSystem: false)))
        XCTAssertFalse(pathEntry.canReset)

        let systemEntry = try entry(for: InventoryFixtures.resolved(
            InventoryFixtures.record(client: "com.apple.Foo"),
            client: ClientStatus(name: "Foo", presence: .missing, isSystem: true, appIdentifier: "com.apple.Foo")))
        XCTAssertFalse(systemEntry.canReset)
    }

    // MARK: - Counts

    func testCounts() {
        let leftover = InventoryFixtures.resolved(
            InventoryFixtures.record(),
            client: ClientStatus(name: "Gone", presence: .missing, isSystem: false))
        let highRisk = InventoryFixtures.resolved(
            InventoryFixtures.record(service: "kTCCServiceSystemPolicyAllFiles"))
        let plain = InventoryFixtures.resolved(
            InventoryFixtures.record(decision: .denied),
            client: ClientStatus(name: "Plain", presence: .installed(path: "/Applications/Plain.app"),
                                 isSystem: false, appIdentifier: "com.plain"))
        let inventory = InventoryFixtures.inventory([leftover, highRisk, plain])

        XCTAssertEqual(inventory.count(.all), 3)
        XCTAssertEqual(inventory.count(.leftovers), 1)
        XCTAssertEqual(inventory.count(.highRisk), 1)
    }

    // MARK: - Filtering and search

    func testEntriesFilterByServiceAndSearch() {
        let zoom = InventoryFixtures.resolved(
            InventoryFixtures.record(service: "kTCCServiceSystemPolicyAllFiles", client: "com.zoom.a"),
            client: ClientStatus(name: "Zoom", presence: .installed(path: "/Applications/Zoom.app"),
                                 isSystem: false, appIdentifier: "com.zoom.a"))
        let evil = InventoryFixtures.resolved(
            InventoryFixtures.record(service: "kTCCServiceMicrophone", client: "com.evil.zoom", decision: .denied),
            client: ClientStatus(name: "Evil Zoom", presence: .installed(path: "/Applications/EvilZoom.app"),
                                 isSystem: false, appIdentifier: "com.evil.zoom"))
        let other = InventoryFixtures.resolved(
            InventoryFixtures.record(service: "kTCCServiceCamera", client: "com.other", decision: .denied),
            client: ClientStatus(name: "Other", presence: .installed(path: "/Applications/Other.app"),
                                 isSystem: false, appIdentifier: "com.other"))
        let buddy = InventoryFixtures.resolved(
            InventoryFixtures.record(service: "kTCCServiceCamera", client: "com.camera.buddy"),
            client: ClientStatus(name: "Camera Buddy", presence: .installed(path: "/Applications/CameraBuddy.app"),
                                 isSystem: false, appIdentifier: "com.camera.buddy"))
        let inventory = InventoryFixtures.inventory([zoom, evil, other, buddy])

        let camera = inventory.entries(filter: .all, service: "kTCCServiceCamera")
        XCTAssertEqual(camera.map(\.record.client), ["com.camera.buddy", "com.other"])

        let zoomSearch = inventory.entries(filter: .all, search: "zoom")
        XCTAssertEqual(Set(zoomSearch.map(\.record.client)), ["com.zoom.a", "com.evil.zoom"])

        let identifierSearch = inventory.entries(filter: .all, search: "com.evil")
        XCTAssertEqual(identifierSearch.map(\.record.client), ["com.evil.zoom"])

        let titleSearch = inventory.entries(filter: .all, search: "camera")
        XCTAssertEqual(Set(titleSearch.map(\.record.client)), ["com.other", "com.camera.buddy"])

        let highRisk = inventory.entries(filter: .highRisk)
        XCTAssertEqual(highRisk.map(\.record.client), ["com.zoom.a"])
    }

    // MARK: - Service counts

    func testServiceCountsFollowCatalogOrder() {
        let cameraA = InventoryFixtures.resolved(InventoryFixtures.record(client: "com.a"))
        let cameraB = InventoryFixtures.resolved(InventoryFixtures.record(client: "com.b"))
        let allFiles = InventoryFixtures.resolved(
            InventoryFixtures.record(service: "kTCCServiceSystemPolicyAllFiles", client: "com.c"))
        let unknown = InventoryFixtures.resolved(
            InventoryFixtures.record(service: "kTCCServiceFooBar", client: "com.d"))
        let inventory = InventoryFixtures.inventory([cameraA, cameraB, allFiles, unknown])

        let counts = inventory.serviceCounts
        XCTAssertEqual(counts.map { $0.service.title }, ["Full Disk Access", "Camera", "Foo Bar"])
        XCTAssertEqual(counts.map { $0.count }, [1, 2, 1])
    }

    // MARK: - Groups

    func testGroupsKeepFirstAppearanceOrderAndShareADatabase() {
        let systemCamera = InventoryFixtures.resolved(
            InventoryFixtures.record(client: "com.aaa", database: .system),
            client: ClientStatus(name: "Aaa", presence: .installed(path: "/Applications/Aaa.app"),
                                 isSystem: false, appIdentifier: "com.aaa"))
        let other = InventoryFixtures.resolved(
            InventoryFixtures.record(service: "kTCCServiceMicrophone", client: "com.zzz"),
            client: ClientStatus(name: "Zzz", presence: .installed(path: "/Applications/Zzz.app"),
                                 isSystem: false, appIdentifier: "com.zzz"))
        let userCamera = InventoryFixtures.resolved(
            InventoryFixtures.record(client: "com.aaa", database: .user),
            client: ClientStatus(name: "Aaa", presence: .installed(path: "/Applications/Aaa.app"),
                                 isSystem: false, appIdentifier: "com.aaa"))
        let entries = InventoryFixtures.inventory([systemCamera, other, userCamera]).entries

        let groups = PermissionInventory.groups(entries)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].identifier, "com.aaa")
        XCTAssertEqual(groups[0].entries.count, 2)
        XCTAssertEqual(groups[0].entries.map(\.record.database), [.system, .user])
        XCTAssertEqual(groups[1].identifier, "com.zzz")
        XCTAssertEqual(groups[1].entries.count, 1)
    }

    // MARK: - Sources

    func testNeedsFullDiskAccessAndUserDatabaseUnavailable() {
        let needsFDA = DatabaseSource(database: .user, reading: .needsFullDiskAccess)
        XCTAssertTrue(InventoryFixtures.inventory([], sources: [needsFDA]).needsFullDiskAccess)
        XCTAssertFalse(InventoryFixtures.inventory([], sources: [DatabaseSource(database: .system, reading: .read([]))]).needsFullDiskAccess)

        XCTAssertTrue(InventoryFixtures.inventory([], sources: [DatabaseSource(database: .user, reading: .missing)]).userDatabaseUnavailable)
        XCTAssertFalse(InventoryFixtures.inventory([], sources: [DatabaseSource(database: .user, reading: .read([]))]).userDatabaseUnavailable)
        XCTAssertFalse(InventoryFixtures.inventory([], sources: [DatabaseSource(database: .user, reading: .needsFullDiskAccess)]).userDatabaseUnavailable,
                       "a refused per-user database is a Full Disk Access problem, not an absent one")
    }

    // MARK: - Ordering

    func testEntriesAreSortedByClientNameThenServiceOrder() {
        let beta = InventoryFixtures.resolved(
            InventoryFixtures.record(client: "com.beta"),
            client: ClientStatus(name: "Beta", presence: .installed(path: "/Applications/Beta.app"),
                                 isSystem: false, appIdentifier: "com.beta"))
        let alpha = InventoryFixtures.resolved(
            InventoryFixtures.record(service: "kTCCServiceMicrophone", client: "com.alpha"),
            client: ClientStatus(name: "Alpha", presence: .installed(path: "/Applications/Alpha.app"),
                                 isSystem: false, appIdentifier: "com.alpha"))
        let byName = InventoryFixtures.inventory([beta, alpha]).entries
        XCTAssertEqual(byName.map(\.client.name), ["Alpha", "Beta"])

        let camera = InventoryFixtures.resolved(
            InventoryFixtures.record(service: "kTCCServiceCamera"),
            client: ClientStatus(name: "Foo", presence: .installed(path: "/Applications/Foo.app"),
                                 isSystem: false, appIdentifier: "com.foo"))
        let allFiles = InventoryFixtures.resolved(
            InventoryFixtures.record(service: "kTCCServiceSystemPolicyAllFiles"),
            client: ClientStatus(name: "Foo", presence: .installed(path: "/Applications/Foo.app"),
                                 isSystem: false, appIdentifier: "com.foo"))
        let byService = InventoryFixtures.inventory([camera, allFiles]).entries
        XCTAssertEqual(byService.map(\.service.title), ["Full Disk Access", "Camera"])
    }


    /// A missing system database or a failed read gets its own warning; a
    /// missing per-user database and Full Disk Access have notices of their own.
    func testProblemSourcesExplainEveryUnreadDatabase() {
        let missingSystem = InventoryFixtures.inventory([], sources: [
            DatabaseSource(database: .system, reading: .missing),
            DatabaseSource(database: .user, reading: .missing),
        ])
        XCTAssertEqual(missingSystem.problemSources.map(\.database), [.system])
        XCTAssertFalse(missingSystem.systemDatabaseRead)

        let failedUser = InventoryFixtures.inventory([], sources: [
            DatabaseSource(database: .system, reading: .read([])),
            DatabaseSource(database: .user, reading: .failed("locked")),
        ])
        XCTAssertEqual(failedUser.problemSources.map(\.database), [.user])
        XCTAssertTrue(failedUser.systemDatabaseRead)

        let noAccess = InventoryFixtures.inventory([], sources: [
            DatabaseSource(database: .system, reading: .needsFullDiskAccess),
            DatabaseSource(database: .user, reading: .missing),
        ])
        XCTAssertTrue(noAccess.problemSources.isEmpty)
        XCTAssertFalse(noAccess.systemDatabaseRead)
    }

    /// Unknown services that derive the same title still sort strictly, so
    /// equal-looking entries keep one stable order.
    func testUnknownServicesWithTheSameTitleSortByIdentifier() {
        XCTAssertEqual(PrivacyService.named("kTCCServiceFooBar").title, PrivacyService.named("FooBar").title)
        let a = PrivacyService.named("FooBar"), b = PrivacyService.named("kTCCServiceFooBar")
        XCTAssertNotEqual(PermissionInventory.serviceOrder(a, b), PermissionInventory.serviceOrder(b, a))

        let records = [
            InventoryFixtures.record(service: "kTCCServiceFooBar", database: .user),
            InventoryFixtures.record(service: "FooBar", database: .system),
            InventoryFixtures.record(service: "kTCCServiceFooBar", database: .system),
        ]
        let entries = InventoryFixtures.inventory(records.map { InventoryFixtures.resolved($0) }).entries
        XCTAssertEqual(entries.map(\.record.service), ["FooBar", "kTCCServiceFooBar", "kTCCServiceFooBar"])
        XCTAssertEqual(entries.map(\.record.database), [.system, .system, .user])
    }
}
