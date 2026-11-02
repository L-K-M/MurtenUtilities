import XCTest
import SwiftUI
import MurtenCore
import MurtenModuleKit
import BootCaptainCore
import BootCaptainKit
@testable import BootCaptainModule

/// The provider as the shell sees it, with a fixture inventory; nothing here
/// reads the live launchd folders or renders the pane (which would scan).
@MainActor
final class ProviderTests: XCTestCase {
    private final class Counter {
        var value = 0
    }

    private let rechecks = Counter()

    private func makeProvider(items: [WatchedStartupItem] = []) -> BootCaptainProvider {
        let name = "BootCaptainModuleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let rechecks = self.rechecks
        let context = ModuleContext(moduleID: StartupWatch.moduleID, defaults: defaults,
                                    requestRecheck: { rechecks.value += 1 }, open: { _ in })
        return BootCaptainProvider(
            context: context,
            inventory: FixtureInventory(snapshot: StartupInventorySnapshot(items: items)))
    }

    func testMatchesTheRegistryEntry() throws {
        let provider = makeProvider()
        let module = try XCTUnwrap(ModuleRegistry.all.first { $0.id == provider.moduleID })
        XCTAssertEqual(module.status, .available)
        XCTAssertEqual(provider.watch?.moduleID, provider.moduleID)
    }

    func testOnlyTheReviewRouteIsOffered() {
        XCTAssertEqual(makeProvider().routeActions, ["review": []])
    }

    func testEverySuggestionRoutePassesTheShellsAllowlist() throws {
        let provider = makeProvider()
        let allowlist = RouteAllowlist(modules: [provider.moduleID], actions: [provider.moduleID: provider.routeActions])
        let finding = StartupWatch.finding(
            for: NewStartupItems(product: StartupProduct(key: "app:x", name: "X"), items: [agent("com.x.y")]),
            at: fixtureDate)
        let content = try XCTUnwrap(provider.watch?.rule.suggestion(for: finding, state: .inactive))
        XCTAssertNoThrow(try allowlist.validate(content.route))
    }

    func testTheWatcherComparesWithWhatThePaneReviewed() async throws {
        let reviewedAgent = agent("com.vendor.known")
        let newAgent = agent("com.vendor.new")
        let provider = makeProvider(items: [reviewedAgent, newAgent])
        let watcher = try XCTUnwrap(provider.watch?.watcher)

        let before = await watcher.observe()
        XCTAssertEqual(before.outcome, .unavailable, "nothing reviewed yet")

        // The pane's first completed scan saw only the known agent.
        provider.scan.apply(ScanResult(
            items: [StartupItem(id: reviewedAgent.id, mechanism: .launchAgent, label: reviewedAgent.label,
                                displayName: reviewedAgent.label)],
            coverage: CoverageReport(), generatedAt: 0))
        XCTAssertEqual(rechecks.value, 1)

        let after = await watcher.observe()
        XCTAssertEqual(after.outcome, .complete)
        XCTAssertEqual(after.findings.map { $0.count("count") }, [1])
        XCTAssertEqual(after.findings.first?.text("labels"), "com.vendor.new")
    }

    func testMakingAPaneChangesNothing() {
        let provider = makeProvider()
        _ = provider.makePane(route: ModuleRoute(moduleID: provider.moduleID, action: StartupWatch.reviewAction))
        _ = provider.makePane(route: nil)
        XCTAssertEqual(provider.scan.filter, .all)
        XCTAssertFalse(provider.scan.isScanning)
    }

    func testNoQuitWarningWhileIdle() {
        XCTAssertNil(makeProvider().interruptionWarning)
    }
}
