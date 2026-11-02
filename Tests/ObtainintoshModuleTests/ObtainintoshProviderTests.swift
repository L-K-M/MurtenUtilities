import XCTest
import MurtenCore
import MurtenModuleKit
import ObtainintoshCore
@testable import ObtainintoshModule
@testable import ObtainintoshServices

@MainActor
final class ObtainintoshProviderTests: XCTestCase {
    func testTheProviderRegistersItsRouteWatcherAndSettings() {
        let fixture = Fixture()
        let provider = ObtainintoshProvider(context: fixture.context(), environment: fixture.environment())

        XCTAssertEqual(provider.moduleID, "obtainintosh")
        XCTAssertEqual(provider.routeActions, ["updates": []])
        XCTAssertNotNil(provider.makeSettings())
        XCTAssertNil(provider.makeMenuSection())
        XCTAssertNil(provider.interruptionWarning)

        let watch = try? XCTUnwrap(provider.watch)
        XCTAssertEqual(watch?.moduleID, "obtainintosh")
        XCTAssertGreaterThanOrEqual(watch?.watcher.cadence.interval ?? 0, 6 * 3600)
        XCTAssertTrue(watch?.watcher.cadence.resources.contains(.network) == true)
    }

    func testTheSuggestionRouteIsAllowedAndCarriesNoSelection() throws {
        let fixture = Fixture()
        let provider = ObtainintoshProvider(context: fixture.context(), environment: fixture.environment())
        let allowlist = RouteAllowlist(modules: ["obtainintosh"], actions: ["obtainintosh": provider.routeActions])

        let route = ModuleRoute(moduleID: "obtainintosh", action: "updates")
        XCTAssertEqual(try allowlist.validate(route), route)
        XCTAssertThrowsError(try allowlist.validate(ModuleRoute(moduleID: "obtainintosh", action: "updates",
                                                                context: ["app": "x"])))
        XCTAssertThrowsError(try allowlist.validate(ModuleRoute(moduleID: "obtainintosh", action: "download")))
    }

    func testCreatingTheProviderTouchesNothingOnDisk() {
        let fixture = Fixture()
        _ = ObtainintoshProvider(context: fixture.context(), environment: fixture.environment())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.listURL.deletingLastPathComponent().path))
    }
}
