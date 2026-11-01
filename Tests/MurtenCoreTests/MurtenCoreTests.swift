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

    func testSuggestionIdentityIsItsDedupeKey() {
        let suggestion = Suggestion(key: "dockvac.reclaimable", moduleID: "dockvac",
                                  title: "Docker is holding ~8 GB", detail: "Unused images and build cache.")
        XCTAssertEqual(suggestion.id, suggestion.key)
    }

    func testWatcherContractFeedsASuggestion() async throws {
        struct DockerDiskWatcher: Watcher {
            let moduleID = "dockvac"
            func poll() async throws -> Suggestion? {
                Suggestion(key: "dockvac.reclaimable", moduleID: moduleID,
                           title: "Docker is holding ~8 GB", detail: "Unused images and build cache.")
            }
        }

        let suggestion = try await DockerDiskWatcher().poll()
        XCTAssertEqual(suggestion?.moduleID, "dockvac")
        XCTAssertEqual(suggestion?.key, "dockvac.reclaimable")
    }
}
