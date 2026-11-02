import XCTest
import MurtenCore
import MurtenModuleKit
import RunningManCore
@testable import RunningManModule

/// The provider as the suite sees it: routes, watcher, preferences, quit guard.
@MainActor
final class RunningManProviderTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "RunningManModuleTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testRoutesAcceptOnlyARunnerIdentifier() throws {
        let provider = makeProvider(demoMode: true)
        XCTAssertEqual(provider.moduleID, "runningman")
        XCTAssertEqual(provider.routeActions, ["runner": ["id"]])

        let allowlist = RouteAllowlist(modules: ["runningman"], actions: ["runningman": provider.routeActions])
        XCTAssertNoThrow(try allowlist.validate(RunnerOfflineRule.route(forRunner: "/Users/example/actions-runners/builder")))
        XCTAssertThrowsError(try allowlist.validate(ModuleRoute(moduleID: "runningman", action: "runner", context: ["force": "1"])))
        XCTAssertThrowsError(try allowlist.validate(ModuleRoute(moduleID: "runningman", action: "start")))
    }

    func testARouteSelectsTheRunnerAndStartsNothing() {
        let provider = makeProvider(demoMode: true)
        let stopped = provider.model.runners.first { $0.status == .stopped }!
        let before = provider.model.runners
        provider.model.section = .overview

        provider.handle(RunnerOfflineRule.route(forRunner: stopped.id))

        XCTAssertEqual(provider.model.section, .runners)
        XCTAssertEqual(provider.model.selectedRunnerID, stopped.id)
        XCTAssertEqual(provider.model.runners, before)
        XCTAssertNil(provider.model.confirmation)
        XCTAssertTrue(provider.model.busyRunnerIDs.isEmpty)
    }

    func testABareRouteAndOtherModulesLeaveThePaneAsItWas() {
        let provider = makeProvider(demoMode: true)
        provider.model.section = .history

        provider.handle(nil)
        provider.handle(ModuleRoute(moduleID: "runningman"))
        provider.handle(ModuleRoute(moduleID: "dockvac", action: "runner", context: ["id": "/x"]))

        XCTAssertEqual(provider.model.section, .history)
    }

    func testTheWatcherAndItsRuleAreRegistered() throws {
        let provider = makeProvider(demoMode: true)
        let watch = try XCTUnwrap(provider.watch)
        XCTAssertEqual(watch.moduleID, "runningman")
        XCTAssertTrue(watch.rule is RunnerOfflineRule)
        XCTAssertGreaterThanOrEqual(watch.watcher.cadence.interval, WatchCadence.minimumInterval)
    }

    func testEverySurfaceExists() async {
        let provider = makeProvider(demoMode: true)
        XCTAssertNotNil(provider.makeSettings())
        XCTAssertNotNil(provider.makeMenuSection())
        let applicability = await provider.applicability()
        XCTAssertEqual(applicability, .applicable, "Without runners the pane is where you register one")
    }

    func testPreferencesGoToTheModuleStoreUnderTheirStandaloneNames() {
        let provider = makeProvider(demoMode: false)
        provider.model.refreshAutomatically = false
        provider.model.lapSoundsEnabled = false
        XCTAssertEqual(defaults.object(forKey: "refreshAutomatically") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "lapSoundsEnabled") as? Bool, false)
        XCTAssertNil(provider.model.quitWarning)
    }

    func testQuittingDuringWorkIsGuarded() throws {
        let provider = makeProvider(demoMode: false)
        XCTAssertNil(provider.interruptionWarning)
        provider.model.isCreating = true
        let warning = try XCTUnwrap(provider.interruptionWarning)
        XCTAssertTrue(warning.contains("A runner is being created."))
    }

    func testNothingPollsUntilSomeoneLooks() {
        let provider = makeProvider(demoMode: false)
        XCTAssertFalse(provider.model.shouldMonitor)
    }

    // MARK: - Fixtures

    private func makeProvider(demoMode: Bool) -> RunningManProvider {
        let context = ModuleContext(moduleID: "runningman", defaults: defaults, requestRecheck: {}, open: { _ in })
        return RunningManProvider(context: context, probe: FixtureProbe(), demoMode: demoMode)
    }
}
