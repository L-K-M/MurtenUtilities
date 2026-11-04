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

    func testModulesUseDescriptiveDisplayNames() {
        let names = Dictionary(uniqueKeysWithValues: ModuleRegistry.all.map { ($0.id, $0.name) })

        XCTAssertEqual(names, [
            "dockvac": "Docker Cleaner",
            "repomen": "Developer Cleanup",
            "bootcaptain": "Startup Manager",
            "devicecontroldoctor": "App Permission Checkup",
            "shortking": "Shortcut Detective",
            "hallpass": "Local Network Access",
            "zenbackupmanager": "Zen Session Recovery",
            "obtainintosh": "Software Update Finder",
            "runningman": "CI Runner Manager",
            "coreography": "System Monitor",
        ])

        for module in ModuleRegistry.all {
            XCTAssertNotEqual(module.name, module.sourceRepository,
                              "\(module.id) exposes its source app name instead of its job")
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
