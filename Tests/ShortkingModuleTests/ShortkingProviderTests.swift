import XCTest
import MurtenCore
import MurtenModuleKit
import ShortkingCore
@testable import ShortkingModule

/// The provider as the shell sees it. Building one reads nothing; these tests
/// never open the pane, which would read the user's Shortking files.
@MainActor
final class ShortkingProviderTests: XCTestCase {

    private func makeProvider() throws -> ShortkingProvider {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ShortkingProviderTests.\(UUID().uuidString)"))
        return ShortkingProvider(context: ModuleContext(
            moduleID: ShortkingProvider.moduleID, defaults: defaults,
            requestRecheck: {}, open: { _ in }))
    }

    func testMatchesItsRegistryEntry() throws {
        let provider = try makeProvider()
        let entry = try XCTUnwrap(ModuleRegistry.all.first { $0.id == provider.moduleID })
        XCTAssertEqual(entry.status, .available)
    }

    func testRegistersTheConflictWatch() throws {
        let watch = try XCTUnwrap(try makeProvider().watch)
        XCTAssertEqual(watch.moduleID, ShortkingSuite.moduleID)
        XCTAssertTrue(watch.watcher is ShortkingWatcher)
        XCTAssertTrue(watch.rule is ShortcutConflictRule)
    }

    func testSuggestionRoutesPassItsAllowlist() throws {
        let provider = try makeProvider()
        let allowlist = RouteAllowlist(modules: [provider.moduleID],
                                       actions: [provider.moduleID: provider.routeActions])
        let route = ShortkingSuite.conflictRoute(comboKey: "k49|m1")

        XCTAssertEqual(try allowlist.validate(route), route)
        XCTAssertThrowsError(try allowlist.validate(
            ModuleRoute(moduleID: provider.moduleID, action: "rebind", context: ["combo": "k49|m1"])))
        XCTAssertThrowsError(try allowlist.validate(
            ModuleRoute(moduleID: provider.moduleID, action: ShortkingSuite.conflictAction,
                        context: ["command": "rm"])))
    }

    func testIsApplicableOnTheSuiteFloor() async throws {
        let provider = try makeProvider()
        let applicability = await provider.applicability()
        XCTAssertEqual(applicability, .applicable)
    }
}
