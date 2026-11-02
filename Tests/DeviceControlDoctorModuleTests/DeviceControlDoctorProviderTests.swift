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
                              defaults: UserDefaults? = nil) -> DeviceControlDoctorProvider {
        let defaults = defaults ?? UserDefaults(suiteName: "DeviceControlDoctorModuleTests.\(UUID().uuidString)")!
        let context = ModuleContext(moduleID: DoctorRoute.moduleID, defaults: defaults,
                                    requestRecheck: { rechecks.count += 1 }, open: { _ in })
        return DeviceControlDoctorProvider(context: context, runner: runner, watchList: mac.watchList, home: mac.home.path)
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
}
