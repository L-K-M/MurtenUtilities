import AppKit
import SwiftUI
import XCTest
import DoctorCore
@testable import DeviceControlDoctorModule

/// Answers each database read from fixtures. A queue per database lets a
/// test give the read after a reset a different answer.
final class FakeDatabaseReader: PrivacyDatabaseReading, @unchecked Sendable {
    private let lock = NSLock()
    private var queues: [PermissionRecord.Database: [DatabaseReading]] = [:]
    private var counts: [PermissionRecord.Database: Int] = [:]

    init(system: DatabaseReading = .read([]), user: DatabaseReading = .missing) {
        queues = [.system: [system], .user: [user]]
    }

    /// The answers for the next reads; the last one repeats.
    func then(_ database: PermissionRecord.Database, _ reading: DatabaseReading) {
        lock.lock(); defer { lock.unlock() }
        queues[database, default: []].append(reading)
    }

    func reads(of database: PermissionRecord.Database) -> Int {
        lock.lock(); defer { lock.unlock() }
        return counts[database] ?? 0
    }

    func read(_ database: PermissionRecord.Database) -> DatabaseReading {
        lock.lock(); defer { lock.unlock() }
        counts[database, default: 0] += 1
        guard var queue = queues[database], let first = queue.first else { return .missing }
        if queue.count > 1 { queue.removeFirst(); queues[database] = queue }
        return first
    }
}

/// Resolves clients from a fixed table; unknown clients are installed apps
/// named after their identifier.
struct FakeClientResolver: ClientResolving {
    var statuses: [String: ClientStatus] = [:]
    var signatures: [String: SignatureCheck] = [:]

    func resolve(_ records: [PermissionRecord]) async -> [ResolvedRecord] {
        records.map { record in
            let client = statuses[record.client]
                ?? ClientStatus(name: record.client, presence: .installed(path: "/Applications/\(record.client).app"),
                                isSystem: false, appIdentifier: record.client)
            return ResolvedRecord(record: record, client: client, signature: signatures[record.client] ?? .matches)
        }
    }
}

@MainActor
final class InventoryStoreTests: XCTestCase {
    private var mac: FixtureMac!
    private var runner: FakeProcessRunner!
    private var opened: [URL] = []
    private var copied: [String] = []
    private var pasteboardAccepts = true

    override func setUp() async throws {
        mac = try FixtureMac()
        runner = FakeProcessRunner()
        opened = []
        copied = []
        pasteboardAccepts = true
    }

    override func tearDown() async throws {
        mac.remove()
    }

    private func record(_ service: String, _ client: String, _ decision: PermissionRecord.Decision = .allowed,
                        database: PermissionRecord.Database = .system, kind: PermissionRecord.ClientKind = .bundleIdentifier,
                        managed: Bool = false) -> PermissionRecord {
        PermissionRecord(database: database, service: service, client: client, clientKind: kind,
                         decision: decision, reason: 4, isManaged: managed)
    }

    private func makeStores(reader: FakeDatabaseReader, resolver: FakeClientResolver = FakeClientResolver())
        -> (DoctorStore, InventoryStore) {
        let doctor = DoctorStore(defaults: UserDefaults(suiteName: "InventoryStoreTests.\(UUID().uuidString)")!,
                                 runner: runner, storageURL: mac.watchList,
                                 settingsOpener: { [unowned self] in self.opened.append($0) })
        let inventory = InventoryStore(doctor: doctor, reader: reader, resolver: resolver, runner: runner,
                                       copyToPasteboard: { [unowned self] in
                                           guard self.pasteboardAccepts else { return false }
                                           self.copied.append($0)
                                           return true
                                       },
                                       systemDescription: "macOS 27.0.1",
                                       now: { Date(timeIntervalSince1970: 1_800_000_000) })
        return (doctor, inventory)
    }

    private var resetCalls: [[String]] {
        runner.calls.filter { $0.first == SystemTool.tccutil && $0.dropFirst().first == "reset" }
    }

    // MARK: - Reading

    func testRefreshReadsBothDatabasesAndClassifiesEntries() async {
        let reader = FakeDatabaseReader(system: .read([
            record("kTCCServiceSystemPolicyAllFiles", "com.example.Backup"),
            record("kTCCServiceCamera", "com.gone.App"),
        ]), user: .missing)
        let resolver = FakeClientResolver(statuses: [
            "com.gone.App": ClientStatus(name: "com.gone.App", presence: .missing, isSystem: false, appIdentifier: "com.gone.App"),
        ])
        let (_, inventory) = makeStores(reader: reader, resolver: resolver)

        await inventory.refresh()

        let read = try? XCTUnwrap(inventory.inventory)
        XCTAssertEqual(read?.entries.count, 2)
        XCTAssertEqual(read?.count(.leftovers), 1)
        XCTAssertEqual(read?.count(.highRisk), 1)
        XCTAssertEqual(read?.userDatabaseUnavailable, true)
        XCTAssertEqual(reader.reads(of: .system), 1)
        XCTAssertEqual(reader.reads(of: .user), 1)
        XCTAssertEqual(inventory.leftovers.map(\.record.client), ["com.gone.App"])
        XCTAssertTrue(runner.calls.isEmpty, "reading spawns no process")
    }

    func testWithoutFullDiskAccessNothingIsShownAsEmpty() async {
        let (_, inventory) = makeStores(reader: FakeDatabaseReader(system: .needsFullDiskAccess, user: .needsFullDiskAccess))
        await inventory.refresh()
        XCTAssertEqual(inventory.inventory?.needsFullDiskAccess, true)
        XCTAssertEqual(inventory.inventory?.entries.count, 0)

        inventory.openFullDiskAccessSettings()
        XCTAssertEqual(opened.map(\.absoluteString), ["x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"])
    }

    func testSelectionFollowsTheServiceAndFallsBackWhenItDisappears() async {
        let reader = FakeDatabaseReader(system: .read([
            record("kTCCServiceCamera", "com.example.Cam"),
            record("kTCCServiceMicrophone", "com.example.Mic"),
        ]))
        reader.then(.system, .read([record("kTCCServiceMicrophone", "com.example.Mic")]))
        let (_, inventory) = makeStores(reader: reader)
        await inventory.refresh()

        inventory.selection = .service("kTCCServiceCamera")
        XCTAssertEqual(inventory.visibleEntries.map(\.record.client), ["com.example.Cam"])
        XCTAssertEqual(inventory.selectionTitle, "Camera")

        await inventory.refresh()
        XCTAssertEqual(inventory.selection, .filter(.all))
        XCTAssertEqual(inventory.visibleEntries.map(\.record.client), ["com.example.Mic"])
    }

    func testSearchNarrowsTheVisibleEntries() async {
        let (_, inventory) = makeStores(reader: FakeDatabaseReader(system: .read([
            record("kTCCServiceCamera", "com.example.Cam"),
            record("kTCCServiceMicrophone", "org.other.Mic"),
        ])))
        await inventory.refresh()
        inventory.search = "org.other"
        XCTAssertEqual(inventory.visibleEntries.map(\.record.client), ["org.other.Mic"])
        XCTAssertEqual(inventory.visibleGroups.count, 1)
    }

    // MARK: - Resets

    func testResetRunsOnlyBundleScopedCommandsAndJudgesThemByAFreshRead() async throws {
        let fullDisk = record("kTCCServiceSystemPolicyAllFiles", "com.example.Backup")
        let camera = record("kTCCServiceCamera", "com.example.Backup", database: .user)
        let reader = FakeDatabaseReader(system: .read([fullDisk]), user: .read([camera]))
        // After the reset Full Disk Access is gone; the camera entry came back.
        reader.then(.system, .read([]))
        reader.then(.user, .read([camera]))
        runner.respond(to: [SystemTool.tccutil, "reset", "SystemPolicyAllFiles", "com.example.Backup"],
                       with: CommandResult(output: "Successfully reset SystemPolicyAllFiles approval status for com.example.Backup", exitCode: 0))
        runner.respond(to: [SystemTool.tccutil, "reset", "Camera", "com.example.Backup"],
                       with: CommandResult(output: "Successfully reset Camera approval status for com.example.Backup", exitCode: 0))
        let (doctor, inventory) = makeStores(reader: reader)
        await inventory.refresh()

        let outcome = await inventory.reset(inventory.inventory?.entries ?? [])
        let result = try XCTUnwrap(outcome)

        XCTAssertEqual(resetCalls, [
            [SystemTool.tccutil, "reset", "SystemPolicyAllFiles", "com.example.Backup"],
            [SystemTool.tccutil, "reset", "Camera", "com.example.Backup"],
        ])
        let outcomes = Dictionary(uniqueKeysWithValues: result.items.map { ($0.entry.service.resetName, $0.outcome) })
        XCTAssertEqual(outcomes["SystemPolicyAllFiles"], .removed)
        XCTAssertEqual(outcomes["Camera"], .stillRecorded)
        XCTAssertEqual(inventory.notice, result.summary)
        XCTAssertEqual(inventory.inventory?.entries.map(\.service.resetName), ["Camera"], "the fresh read is shown")
        XCTAssertFalse(doctor.isRepairing, "the module's repair lock is released")
        XCTAssertFalse(inventory.isResetting)
    }

    func testResetNeverTouchesSystemManagedOrPathEntries() async throws {
        let reader = FakeDatabaseReader(system: .read([
            record("kTCCServiceAccessibility", "com.apple.screensharing.agent"),
            record("kTCCServiceScreenCapture", "com.example.Managed", managed: true),
            record("kTCCServiceSystemPolicyAllFiles", "/usr/local/bin/tool", kind: .path),
        ]))
        let resolver = FakeClientResolver(statuses: [
            "com.apple.screensharing.agent": ClientStatus(name: "com.apple.screensharing.agent", presence: .missing, isSystem: true),
        ])
        let (_, inventory) = makeStores(reader: reader, resolver: resolver)
        await inventory.refresh()

        let outcome = await inventory.reset(inventory.inventory?.entries ?? [])
        let result = try XCTUnwrap(outcome)

        XCTAssertEqual(resetCalls, [])
        XCTAssertEqual(result.items.count, 3)
        XCTAssertTrue(result.items.allSatisfy { $0.outcome == .skipped })
    }

    func testAFailedCommandKeepsItsAnswer() async throws {
        let reader = FakeDatabaseReader(system: .read([record("kTCCServiceCamera", "com.gone.App")]))
        runner.respond(to: [SystemTool.tccutil, "reset", "Camera", "com.gone.App"], with: CommandResult(
            output: "tccutil: No such bundle identifier \"com.gone.App\": The operation couldn’t be completed. (OSStatus error -10814.)",
            exitCode: 64))
        let (_, inventory) = makeStores(reader: reader)
        await inventory.refresh()

        let outcome = await inventory.reset(inventory.inventory?.entries ?? [])
        let result = try XCTUnwrap(outcome)

        guard case .failed(let detail) = result.items.first?.outcome else { return XCTFail("expected a failure") }
        XCTAssertTrue(detail.contains("No such bundle identifier"), detail)
        XCTAssertTrue(result.summary.contains("did not reset 1 entry"), result.summary)
    }

    /// A timed-out command is judged by the fresh read, not reported as a
    /// failure: gone is removed, still there is uncertain.
    func testAnUncertainCommandIsJudgedByTheFreshRead() async throws {
        let camera = record("kTCCServiceCamera", "com.example.Cam")
        let microphone = record("kTCCServiceMicrophone", "com.example.Cam")
        let reader = FakeDatabaseReader(system: .read([camera, microphone]))
        reader.then(.system, .read([microphone]))
        runner.respond(to: [SystemTool.tccutil, "reset", "Camera", "com.example.Cam"],
                       with: CommandResult(output: "", exitCode: 15, timedOut: true))
        runner.respond(to: [SystemTool.tccutil, "reset", "Microphone", "com.example.Cam"],
                       with: CommandResult(output: "", exitCode: 15, timedOut: true))
        let (_, inventory) = makeStores(reader: reader)
        await inventory.refresh()

        let outcome = await inventory.reset(inventory.inventory?.entries ?? [])
        let result = try XCTUnwrap(outcome)

        let outcomes = Dictionary(uniqueKeysWithValues: result.items.map { ($0.entry.service.resetName, $0.outcome) })
        XCTAssertEqual(outcomes["Camera"], .removed)
        guard case .uncertain(let detail) = outcomes["Microphone"] else { return XCTFail("expected uncertain") }
        XCTAssertTrue(detail.contains("timed out"), detail)
        XCTAssertFalse(result.summary.contains("did not reset"), result.summary)
        XCTAssertTrue(result.summary.contains("uncertain for 1 entry"), result.summary)
    }

    /// A command tccutil reported failing changed nothing, so the watched
    /// app keeps its test evidence and gets no reset event.
    func testAFailedResetKeepsTheWatchedAppsEvidence() async throws {
        let reader = FakeDatabaseReader(system: .read([record("kTCCServiceAccessibility", "com.example.Watched")]))
        runner.respond(to: [SystemTool.tccutil, "reset", "Accessibility", "com.example.Watched"],
                       with: CommandResult(output: "tccutil: No such bundle identifier", exitCode: 64))
        let (doctor, inventory) = makeStores(reader: reader)
        var watched = WatchedApp(name: "Watched", bundleID: "com.example.Watched", path: "/Applications/Watched.app", version: "1")
        watched.functionalTest = .init(outcome: .passed, note: "ok", appPath: watched.path, appVersion: "1")
        doctor.apps = [watched]
        await inventory.refresh()

        let outcome = await inventory.reset(inventory.inventory?.entries ?? [])

        XCTAssertNotNil(outcome)
        XCTAssertNotNil(doctor.apps[0].functionalTest)
        XCTAssertFalse(doctor.events.contains { $0.message.contains("All permissions") })
        XCTAssertFalse(doctor.isRepairing)
    }

    func testAResetWhoseDatabaseCannotBeReadAgainIsUnverified() async throws {
        let reader = FakeDatabaseReader(system: .read([record("kTCCServiceCamera", "com.example.Cam")]))
        reader.then(.system, .needsFullDiskAccess)
        runner.respond(to: [SystemTool.tccutil, "reset", "Camera", "com.example.Cam"], with: CommandResult(output: "", exitCode: 0))
        let (_, inventory) = makeStores(reader: reader)
        await inventory.refresh()

        let outcome = await inventory.reset(inventory.inventory?.entries ?? [])
        let result = try XCTUnwrap(outcome)
        XCTAssertEqual(result.items.first?.outcome, .unverified)
    }

    func testResetWaitsForTheModuleRepairLock() async {
        let reader = FakeDatabaseReader(system: .read([record("kTCCServiceCamera", "com.example.Cam")]))
        let (doctor, inventory) = makeStores(reader: reader)
        await inventory.refresh()
        doctor.isRepairing = true

        let result = await inventory.reset(inventory.inventory?.entries ?? [])

        XCTAssertNil(result)
        XCTAssertEqual(resetCalls, [])
        XCTAssertNotNil(doctor.notice)
        XCTAssertTrue(doctor.isRepairing, "another operation's lock is left alone")
    }

    func testResetClearsTestEvidenceOfAffectedWatchedApps() async throws {
        let reader = FakeDatabaseReader(system: .read([record("kTCCServiceAccessibility", "com.example.Watched")]))
        runner.respond(to: [SystemTool.tccutil, "reset", "Accessibility", "com.example.Watched"], with: CommandResult(output: "", exitCode: 0))
        let (doctor, inventory) = makeStores(reader: reader)
        var watched = WatchedApp(name: "Watched", bundleID: "com.example.Watched", path: "/Applications/Watched.app", version: "1")
        watched.functionalTest = .init(outcome: .passed, note: "ok", appPath: watched.path, appVersion: "1")
        var other = WatchedApp(name: "Other", bundleID: "com.example.Other", path: "/Applications/Other.app", version: "1")
        other.functionalTest = .init(outcome: .passed, note: "ok", appPath: other.path, appVersion: "1")
        doctor.apps = [watched, other]
        await inventory.refresh()

        let outcome = await inventory.reset(inventory.inventory?.entries ?? [])
        XCTAssertNotNil(outcome)

        XCTAssertNil(doctor.apps.first { $0.bundleID == "com.example.Watched" }?.functionalTest)
        XCTAssertNotNil(doctor.apps.first { $0.bundleID == "com.example.Other" }?.functionalTest)
        XCTAssertTrue(doctor.events.contains { $0.appName == "Watched" && $0.message.contains("All permissions") })
    }

    // MARK: - Report and Settings

    func testCopyReportPutsThePlainTextReportOnThePasteboard() async {
        let (_, inventory) = makeStores(reader: FakeDatabaseReader(system: .read([record("kTCCServiceCamera", "com.example.Cam")])))
        inventory.copyReport()
        XCTAssertTrue(copied.isEmpty, "nothing to copy before a read")

        await inventory.refresh()
        inventory.copyReport()

        XCTAssertEqual(copied.count, 1)
        XCTAssertTrue(copied[0].hasPrefix("App Permission Checkup: privacy permissions\n"), copied[0])
        XCTAssertTrue(copied[0].contains("on macOS 27.0.1"), copied[0])
        XCTAssertTrue(copied[0].contains("Camera (kTCCServiceCamera), 1"), copied[0])
        XCTAssertTrue(inventory.notice?.contains("review it before you share it") == true)
    }

    func testCopyReportSaysWhenThePasteboardRefuses() async {
        let (_, inventory) = makeStores(reader: FakeDatabaseReader(system: .read([record("kTCCServiceCamera", "com.example.Cam")])))
        await inventory.refresh()
        pasteboardAccepts = false

        inventory.copyReport()

        XCTAssertEqual(inventory.notice, "The report could not be put on the clipboard. Try Copy Report again.")
    }

    func testSettingsLinksUseTheServiceListOrThePrivacyPage() {
        let (_, inventory) = makeStores(reader: FakeDatabaseReader())
        inventory.openSettings(PrivacyService.named("kTCCServiceCamera"))
        inventory.openSettings(PrivacyService.named("kTCCServiceSomethingNew"))
        XCTAssertEqual(opened.map(\.absoluteString), [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera",
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
        ])
    }

    // MARK: - Layout

    func testTheDetailViewHostsHundredsOfEntriesWithoutRunningAnything() async throws {
        let records = (0..<300).map { record($0 % 2 == 0 ? "kTCCServiceCamera" : "kTCCServiceSystemPolicyAllFiles", "com.example.App\($0 / 2)") }
        let (doctor, inventory) = makeStores(reader: FakeDatabaseReader(system: .read(records), user: .missing))
        await inventory.refresh()
        let host = NSHostingView(rootView: InventoryDetailView().environmentObject(doctor).environmentObject(inventory))
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 650)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertLessThanOrEqual(host.fittingSize.height, 650)
        XCTAssertTrue(runner.calls.isEmpty, "showing the inventory never runs tccutil")
    }

    func testTheResetSheetScrollsInsteadOfGrowing() async throws {
        let records = (0..<120).map { record("kTCCServiceCamera", "com.example.Left\($0)") }
        let resolver = FakeClientResolver(statuses: Dictionary(uniqueKeysWithValues: (0..<120).map {
            ("com.example.Left\($0)", ClientStatus(name: "Left \($0)", presence: .missing, isSystem: false))
        }))
        let (doctor, inventory) = makeStores(reader: FakeDatabaseReader(system: .read(records)), resolver: resolver)
        await inventory.refresh()
        let request = InventoryResetRequest(cleanup: inventory.leftovers)
        XCTAssertEqual(request.units.count, 120)
        XCTAssertEqual(request.preselected.count, 120)

        let host = NSHostingView(rootView: InventoryResetSheet(request: request).environmentObject(doctor).environmentObject(inventory))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 640)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertLessThanOrEqual(host.fittingSize.height, 640)
        XCTAssertEqual(resetCalls, [], "opening the confirmation resets nothing")
    }
}
