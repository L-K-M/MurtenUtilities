import Foundation
import XCTest
import MurtenCore
import MurtenModuleKit
import CoreographyCore
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices
@testable import CoreographyModule

@MainActor
final class CoreographyProviderTests: XCTestCase {
    /// A fresh module store per test, removed afterwards.
    private func makeDefaults() throws -> UserDefaults {
        let suite = "CoreographyProviderTests.\(UUID())"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    private func makeProvider(observer: any SystemObserving = QuietSystem()) throws -> CoreographyProvider {
        let context = ModuleContext(moduleID: "coreography", defaults: try makeDefaults(), requestRecheck: {}, open: { _ in })
        return CoreographyProvider(context: context, observer: observer)
    }

    func testRegistersTheWatcherAndRuleForItsModule() throws {
        let provider = try makeProvider()
        let watch = try XCTUnwrap(provider.watch)
        XCTAssertEqual(provider.moduleID, "coreography")
        XCTAssertEqual(watch.moduleID, "coreography")
        XCTAssertGreaterThanOrEqual(watch.watcher.cadence.interval, WatchCadence.minimumInterval)
        XCTAssertFalse(watch.watcher.cadence.resources.contains(.network), "every read is local")
        XCTAssertTrue(watch.rule is CoreographyRule)
    }

    func testTheWatcherReadsOnlyThroughTheInjectedObserver() async throws {
        let provider = try makeProvider(observer: QuietSystem())
        let watch = try XCTUnwrap(provider.watch)
        let observation = await watch.watcher.observe()
        XCTAssertEqual(observation.moduleID, "coreography")
        XCTAssertTrue(observation.failures.isEmpty)
        XCTAssertTrue(observation.completedScopes.isSuperset(of: [CoreographyWatch.memoryScope, CoreographyWatch.thermalScope,
                                                                   CoreographyWatch.startupVolumeScope]))
    }

    func testEveryRouteTheRuleBuildsIsAllowedByTheProvider() throws {
        let provider = try makeProvider()
        let allowlist = RouteAllowlist(modules: ["coreography"], actions: ["coreography": provider.routeActions])
        let routes = [
            CoreographyWatch.route(CoreographyWatch.Action.process, context: [CoreographyWatch.nameContextKey: "Xcode"]),
            CoreographyWatch.route(CoreographyWatch.Action.memory),
            CoreographyWatch.route(CoreographyWatch.Action.thermal),
            CoreographyWatch.route(CoreographyWatch.Action.storage),
            ModuleRoute(moduleID: "coreography")
        ]
        for route in routes { XCTAssertEqual(try allowlist.validate(route), route) }
        XCTAssertThrowsError(try allowlist.validate(ModuleRoute(moduleID: "coreography", action: "process",
                                                                context: ["pid": "1"])), "only a name narrows the table")
        XCTAssertThrowsError(try allowlist.validate(ModuleRoute(moduleID: "coreography", action: "kill")))
    }

    func testAskingForSurfacesDoesNotStartTheSession() throws {
        let provider = try makeProvider()
        XCTAssertNotNil(provider.makeMenuSection())
        XCTAssertNotNil(provider.makeSettings())
        XCTAssertNil(provider.interruptionWarning)
        XCTAssertFalse(provider.hasSession, "the shell asks for these only to learn whether they exist")
    }

    // MARK: - Navigation

    private func fixtureModel() throws -> DashboardModel {
        DashboardModel(monitor: try SystemMonitor(driver: StillHost()), interval: .seconds(60), preferences: try makeDefaults())
    }

    func testAProcessRouteFiltersTheTableAndSelectsNothing() throws {
        let model = try fixtureModel()
        model.detailPane = .sensors
        CoreographyNavigation.apply(
            CoreographyWatch.route(CoreographyWatch.Action.process, context: [CoreographyWatch.nameContextKey: "Xcode"]), to: model)
        XCTAssertEqual(model.section, .processes)
        XCTAssertEqual(model.detailPane, .processes)
        XCTAssertEqual(model.processSort, .cpu)
        XCTAssertEqual(model.processFilter, "Xcode")
        XCTAssertNil(model.selectedProcessRow, "a suggestion never selects a process to act on")
    }

    func testOtherRoutesOnlyChangeTheView() throws {
        let model = try fixtureModel()
        CoreographyNavigation.apply(CoreographyWatch.route(CoreographyWatch.Action.memory), to: model)
        XCTAssertEqual(model.section, .memory)
        XCTAssertEqual(model.processSort, .memory)
        CoreographyNavigation.apply(CoreographyWatch.route(CoreographyWatch.Action.storage), to: model)
        XCTAssertEqual(model.section, .storage)
        XCTAssertEqual(model.processSort, .diskWrite)
        CoreographyNavigation.apply(CoreographyWatch.route(CoreographyWatch.Action.thermal), to: model)
        XCTAssertEqual(model.section, .power)
        XCTAssertEqual(model.detailPane, .sensors)

        model.processFilter = "mine"
        CoreographyNavigation.apply(ModuleRoute(moduleID: "coreography"), to: model)
        CoreographyNavigation.apply(ModuleRoute(moduleID: "dockvac", action: "process", context: ["name": "x"]), to: model)
        XCTAssertEqual(model.processFilter, "mine", "a bare or foreign route leaves the pane as it was")
        XCTAssertEqual(model.section, .power)
    }
}

/// A Mac with nothing to report.
private struct QuietSystem: SystemObserving {
    func processCPUTimes() async -> Result<[ProcessCPUTime], ObservationFailure> { .success([]) }
    func memoryPressure() async -> Result<ObservedMemoryPressure, ObservationFailure> { .success(.normal) }
    func thermalPressure() async -> Result<ObservedThermalPressure, ObservationFailure> { .success(.nominal) }
    func startupVolume() async -> Result<VolumeSpace, ObservationFailure> {
        .success(VolumeSpace(totalBytes: 1_000_000_000_000, availableBytes: 600_000_000_000))
    }
}

/// A host that is never sampled in these tests.
private actor StillHost: HostSampleReading {
    func read() async -> RawHostSnapshot {
        RawHostSnapshot(
            clockID: UUID(), monotonicNanoseconds: 0, wallTime: Date(timeIntervalSince1970: 1_700_000_000),
            inventory: HostInventory(operatingSystem: "Fixture", architecture: "fixture", logicalCPUCount: 1, physicalMemoryBytes: 1 << 20),
            cpu: .failure(.unsupportedPlatform), memory: .failure(.unsupportedPlatform),
            swap: .failure(.unsupportedPlatform), memoryPressure: .failure(.unsupportedPlatform),
            thermalPressure: .failure(.unsupportedPlatform)
        )
    }
}
