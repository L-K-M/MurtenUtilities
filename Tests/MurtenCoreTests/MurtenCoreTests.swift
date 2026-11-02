import XCTest
@testable import MurtenCore

final class MurtenCoreTests: XCTestCase {
    func testModuleIDsAreUnique() {
        let ids = ModuleRegistry.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "module ids must be unique — they key deep links and suggestions")
    }

    func testEveryModuleHasHomeScreenText() {
        for module in ModuleRegistry.all {
            XCTAssertFalse(module.name.isEmpty, "\(module.id) lacks a name")
            XCTAssertFalse(module.summary.isEmpty, "\(module.id) lacks its one-line summary")
            XCTAssertFalse(module.systemImage.isEmpty, "\(module.id) lacks an icon")
        }
    }

    func testModuleIDsAreRouteIdentifiers() throws {
        let allowlist = RouteAllowlist(modules: Set(ModuleRegistry.all.map(\.id)))
        for module in ModuleRegistry.all {
            let route = try allowlist.route(from: ModuleRoute(moduleID: module.id).url)
            XCTAssertEqual(route.moduleID, module.id)
        }
    }

    func testSuggestionKeyRendersModuleConditionAndScope() {
        XCTAssertEqual(reclaimable(5 * gigabyte).key.description,
                       "dockvac.reclaimable@unix:///var/run/docker.sock")
    }
}
