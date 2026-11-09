import XCTest
import DoctorCore
import MurtenCore
import MurtenModuleKit
@testable import DeviceControlDoctorModule

/// The provider as the shell sees it: routes, windows, settings, menu
/// section and the store's state, all against fixtures.
final class DeviceControlDoctorProviderTests: XCTestCase {
    private final class Rechecks {
        var count = 0
    }

    @MainActor
    private func makeProvider(mac: FixtureMac, runner: FakeProcessRunner, rechecks: Rechecks = Rechecks(),
                              defaults: UserDefaults? = nil,
                              lifecycle: (any ApplicationLifecycleManaging)? = nil) -> DeviceControlDoctorProvider {
        let defaults = defaults ?? UserDefaults(suiteName: "DeviceControlDoctorModuleTests.\(UUID().uuidString)")!
        let context = ModuleContext(moduleID: DoctorRoute.moduleID, defaults: defaults,
                                    requestRecheck: { rechecks.count += 1 }, open: { _ in })
        return DeviceControlDoctorProvider(context: context, runner: runner, watchList: mac.watchList,
                                           home: mac.home.path, lifecycle: lifecycle, settingsOpener: { _ in })
    }

    @MainActor
    func testRegistersTheReviewRouteAndTheWatcher() throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        let provider = makeProvider(mac: mac, runner: FakeProcessRunner())

        XCTAssertEqual(provider.moduleID, "devicecontroldoctor")
        XCTAssertTrue(ModuleRegistry.all.contains { $0.id == provider.moduleID && $0.status == .available })
        XCTAssertEqual(provider.routeActions, ["review": ["app"]])
        let allowlist = RouteAllowlist(modules: [provider.moduleID], actions: [provider.moduleID: provider.routeActions])
        let route = DoctorRoute.review(appID: UUID())
        XCTAssertEqual(try allowlist.validate(route), route)
        XCTAssertThrowsError(try allowlist.validate(ModuleRoute(moduleID: provider.moduleID, action: "reset",
                                                                context: ["app": UUID().uuidString])))

        let watch = try XCTUnwrap(provider.watch)
        XCTAssertEqual(watch.moduleID, provider.moduleID)
        XCTAssertTrue(watch.rule is VerificationRule)
        XCTAssertGreaterThanOrEqual(watch.watcher.cadence.interval, WatchCadence.minimumInterval)
    }

    @MainActor
    func testOffersTestPadSettingsAndMenuSection() throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        let provider = makeProvider(mac: mac, runner: FakeProcessRunner())

        XCTAssertNotNil(provider.makeWindow(ModuleWindowRequest(moduleID: "devicecontroldoctor", kind: "test-pad")))
        XCTAssertNil(provider.makeWindow(ModuleWindowRequest(moduleID: "devicecontroldoctor", kind: "other")))
        XCTAssertNil(provider.makeWindow(ModuleWindowRequest(moduleID: "dockvac", kind: "test-pad")))
        XCTAssertNotNil(provider.makeSettings())
        XCTAssertNotNil(provider.makeMenuSection())
        XCTAssertNil(provider.interruptionWarning)
    }

    @MainActor
    func testCreatingTheModuleRunsNothingAndReadsTheWatchListInPlace() throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        let app = try mac.installApp("PopChar", bundleID: "de.ergonis.PopChar")
        try mac.saveWatchList([app])
        let saved = try Data(contentsOf: mac.watchList)
        let runner = FakeProcessRunner()

        let provider = makeProvider(mac: mac, runner: runner)
        _ = provider.makePane(route: nil)
        _ = provider.makeMenuSection()

        XCTAssertTrue(runner.calls.isEmpty, "nothing runs before the pane appears or the user asks")
        XCTAssertEqual(provider.store.apps.map(\.id), [app.id])
        XCTAssertEqual(provider.store.selectedID, app.id)
        XCTAssertEqual(try Data(contentsOf: mac.watchList), saved, "loading never rewrites the list")
    }

    @MainActor
    func testUnreadableWatchListIsNeverOverwritten() throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        try FileManager.default.createDirectory(at: mac.watchList.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("not json".utf8)
        try original.write(to: mac.watchList)

        let provider = makeProvider(mac: mac, runner: FakeProcessRunner())
        let newApp = try mac.installApp("New", bundleID: "com.example.New")
        provider.store.addApps([newApp])

        XCTAssertNotNil(provider.store.notice)
        XCTAssertEqual(try Data(contentsOf: mac.watchList), original)
    }

    @MainActor
    func testReviewRouteSelectsTheAppAndStartsNoRepair() throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        let first = try mac.installApp("First", bundleID: "com.example.First")
        let second = try mac.installApp("Second", bundleID: "com.example.Second")
        try mac.saveWatchList([first, second])
        let runner = FakeProcessRunner()
        let provider = makeProvider(mac: mac, runner: runner)

        provider.store.apply(DoctorRoute.review(appID: second.id))
        XCTAssertEqual(provider.store.selectedID, second.id)
        XCTAssertFalse(provider.store.isRepairing)
        XCTAssertFalse(runner.ranReset)

        provider.store.apply(DoctorRoute.review(appID: UUID()))
        XCTAssertEqual(provider.store.selectedID, second.id)
        XCTAssertEqual(provider.store.notice, "The app from that suggestion is no longer on your watch list.")
    }

    @MainActor
    func testMonitoringPreferenceLivesInTheModuleDefaults() throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        let defaults = UserDefaults(suiteName: "DeviceControlDoctorModuleTests.\(UUID().uuidString)")!

        let provider = makeProvider(mac: mac, runner: FakeProcessRunner(), defaults: defaults)
        XCTAssertTrue(provider.store.monitorEnabled, "on by default, as in the standalone app")
        provider.store.monitorEnabled = false
        XCTAssertEqual(defaults.object(forKey: "monitorEnabled") as? Bool, false)

        XCTAssertFalse(makeProvider(mac: mac, runner: FakeProcessRunner(), defaults: defaults).store.monitorEnabled)
    }

    @MainActor
    func testUserChangesAskForARecheck() throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        let app = try mac.installApp("PopChar", bundleID: "de.ergonis.PopChar")
        try mac.saveWatchList([app])
        let rechecks = Rechecks()
        let provider = makeProvider(mac: mac, runner: FakeProcessRunner(), rechecks: rechecks)

        provider.store.setExpected(.postEvent, enabled: true, appID: app.id)
        provider.store.recordTest(appID: app.id, outcome: .passed, note: "Typed a token")
        provider.store.removeApp(app.id)

        XCTAssertEqual(rechecks.count, 3)
        guard case .loaded(let saved) = WatchListFile.read(at: mac.watchList) else { return XCTFail("list not saved") }
        XCTAssertTrue(saved.apps.isEmpty)
    }

    @MainActor
    func testScopedRecordingResetReportsCommandSuccessNotEffectiveAccess() async throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        let app = try mac.installApp("Teams", bundleID: "com.microsoft.teams2")
        try mac.saveWatchList([app])
        let runner = FakeProcessRunner()
        runner.withholdListing()
        runner.respond(to: [SystemTool.tccutil, "reset", "ScreenCapture", app.bundleID],
                       with: CommandResult(output: "Successfully reset", exitCode: 0))
        let defaults = UserDefaults(suiteName: "ScopedRecordingResetTests.\(UUID().uuidString)")!
        var openedURLs: [URL] = []
        var rechecks = 0
        let store = DoctorStore(defaults: defaults, runner: runner, storageURL: mac.watchList,
                                settingsOpener: { openedURLs.append($0) }, watchListChanged: { rechecks += 1 })
        store.apps[0].functionalTest = .init(outcome: .passed, note: "Worked", appPath: app.path, appVersion: app.version)

        // The fixture uses Teams' real identifier. Never quit or launch the
        // live app; the only reset command runs through the fake boundary.
        let result = await store.reset(appID: app.id, services: [.screenCapture], quitFirst: false, reopen: false)

        XCTAssertTrue(result, "a scoped reset does not require an empty service-wide client list")
        XCTAssertEqual(runner.calls.first, [SystemTool.tccutil, "reset", "ScreenCapture", app.bundleID])
        XCTAssertEqual(runner.calls.filter { $0.dropFirst().first == "reset" }, [
            [SystemTool.tccutil, "reset", "ScreenCapture", app.bundleID]
        ])
        XCTAssertEqual(openedURLs.map(\.absoluteString), ["x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"])
        XCTAssertTrue(store.notice?.contains("reported successful reset commands") == true)
        XCTAssertTrue(store.notice?.contains("Effective access has not been verified") == true)
        XCTAssertTrue(store.notice?.contains("MDM") == true)
        XCTAssertFalse(store.events.contains { $0.message.contains("User approval is required again") })
        XCTAssertNil(store.apps[0].functionalTest)
        XCTAssertEqual(store.apps[0].expectedServices, app.expectedServices)
        XCTAssertEqual(rechecks, 1)
        XCTAssertFalse(store.isRepairing)
    }

    @MainActor
    func testPartialRecordingResetDoesNotReportAllCommandsCompleted() async throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        let app = try mac.installApp("Teams", bundleID: "com.microsoft.teams2")
        try mac.saveWatchList([app])
        let runner = FakeProcessRunner()
        runner.respond(to: [SystemTool.tccutil, "reset", "ScreenCapture", app.bundleID],
                       with: CommandResult(output: "", exitCode: 0))
        runner.respond(to: [SystemTool.tccutil, "reset", "AudioCapture", app.bundleID],
                       with: CommandResult(output: "Reset denied", exitCode: 1))
        let provider = makeProvider(mac: mac, runner: runner)

        let result = await provider.store.reset(appID: app.id, services: [.screenCapture, .audioCapture], quitFirst: false, reopen: false)

        XCTAssertFalse(result)
        XCTAssertTrue(provider.store.notice?.contains("Screen & System Audio Recording") == true)
        XCTAssertTrue(provider.store.notice?.contains("System Audio Recording Only: Reset denied") == true)
        XCTAssertTrue(provider.store.notice?.contains("MDM") == true)
        XCTAssertFalse(provider.store.isRepairing)
    }

    @MainActor
    func testScopedRecordingResetRevalidatesTheAppBeforeWriting() async throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        let app = try mac.installApp("Teams", bundleID: "com.microsoft.teams2")
        try mac.saveWatchList([app])
        let runner = FakeProcessRunner()
        let provider = makeProvider(mac: mac, runner: runner)
        try mac.writeInfo(bundleID: "com.example.Replaced", name: "Replacement", at: URL(fileURLWithPath: app.path))

        let result = await provider.store.reset(appID: app.id, services: [.screenCapture], quitFirst: false, reopen: false)

        XCTAssertFalse(result)
        XCTAssertFalse(runner.ranReset)
        XCTAssertTrue(provider.store.notice?.contains("bundle identifier changed") == true)
    }

    @MainActor
    func testResetAllClearsFunctionalEvidenceAndRequestsARecheck() async throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        let app = try mac.installApp("PopChar", bundleID: "de.ergonis.PopChar")
        try mac.saveWatchList([app])
        let runner = resetAllRunner()
        let lifecycle = StoreLifecycle()
        let rechecks = Rechecks()
        let provider = makeProvider(mac: mac, runner: runner, rechecks: rechecks, lifecycle: lifecycle)
        provider.store.apps[0].functionalTest = .init(outcome: .passed, note: "Worked",
                                                       appPath: app.path, appVersion: app.version)

        let result = await provider.store.resetAllPermissions()

        XCTAssertTrue(result)
        XCTAssertNil(provider.store.apps[0].functionalTest)
        XCTAssertEqual(rechecks.count, 1)
        XCTAssertTrue(provider.store.notice?.contains("Reset all") == true)
        XCTAssertFalse(provider.store.isRepairing)
    }

    @MainActor
    func testResetAllFailurePreservesFunctionalEvidence() async throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        let app = try mac.installApp("PopChar", bundleID: "de.ergonis.PopChar")
        try mac.saveWatchList([app])
        let runner = FakeProcessRunner()
        runner.withholdListing()
        let rechecks = Rechecks()
        let provider = makeProvider(mac: mac, runner: runner, rechecks: rechecks, lifecycle: StoreLifecycle())
        provider.store.apps[0].functionalTest = .init(outcome: .passed, note: "Worked",
                                                       appPath: app.path, appVersion: app.version)

        let result = await provider.store.resetAllPermissions()

        XCTAssertFalse(result)
        XCTAssertNotNil(provider.store.apps[0].functionalTest)
        XCTAssertEqual(rechecks.count, 0)
        XCTAssertFalse(runner.ranReset)
    }

    @MainActor
    func testUncertainResetClearsEvidenceAndRequestsARecheck() async throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        let app = try mac.installApp("PopChar", bundleID: "de.ergonis.PopChar")
        try mac.saveWatchList([app])
        let runner = resetAllRunner()
        let listed = CommandResult(output: "de.ergonis.PopChar", exitCode: 0)
        runner.respond(to: [SystemTool.tccutil, "list", "-s", "Accessibility"], with: [
            listed, listed, listed, listed, listed,
            CommandResult(output: "", exitCode: -1, timedOut: true)
        ])
        let rechecks = Rechecks()
        let provider = makeProvider(mac: mac, runner: runner, rechecks: rechecks,
                                    lifecycle: StoreLifecycle())
        provider.store.apps[0].functionalTest = .init(outcome: .passed, note: "Worked",
                                                       appPath: app.path, appVersion: app.version)

        let result = await provider.store.resetAllPermissions()

        XCTAssertFalse(result)
        XCTAssertNil(provider.store.apps[0].functionalTest,
                     "a reset command may have changed TCC even when verification failed")
        XCTAssertEqual(rechecks.count, 1)
        XCTAssertTrue(provider.store.notice?.contains("Completed before stopping") == false)
    }

    private func resetAllRunner() -> FakeProcessRunner {
        let runner = FakeProcessRunner()
        runner.clearListedServiceAfterReset()
        runner.offerListing()
        for service in GlobalRepairPlan().services {
            runner.respond(to: [SystemTool.tccutil, "list", "-s", service.rawValue],
                           with: CommandResult(output: "de.ergonis.PopChar", exitCode: 0))
            runner.respond(to: [SystemTool.tccutil, "reset", service.rawValue],
                           with: CommandResult(output: "", exitCode: 0))
        }
        return runner
    }
}

@MainActor
private final class StoreLifecycle: ApplicationLifecycleManaging {
    func runningProcesses(matching clients: Set<String>) async throws -> [AffectedProcess] { [] }
    func requestTermination(of processes: [AffectedProcess]) {}
}
