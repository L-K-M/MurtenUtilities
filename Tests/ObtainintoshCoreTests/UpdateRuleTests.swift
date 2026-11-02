import XCTest
import MurtenCore
@testable import ObtainintoshCore

final class UpdateRuleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let app = TrackedApp(id: "app-1", name: "Tool", sourceType: .github, sourceURL: "https://github.com/o/tool")

    func testANewerReleaseIsSuggestedAndOpensTheUpdatesRoute() throws {
        let finding = UpdateFinding.make(app: app, installed: "1.2.0", latest: "1.3.0", at: now)
        let content = try XCTUnwrap(UpdateRule().suggestion(for: finding, state: .inactive))

        XCTAssertEqual(content.title, "Tool 1.3.0 is available")
        XCTAssertTrue(content.detail.contains("1.2.0"))
        XCTAssertEqual(content.route, ModuleRoute(moduleID: "obtainintosh", action: "updates"))
        XCTAssertTrue(content.route.context.isEmpty, "a suggestion preselects nothing")
        XCTAssertEqual(finding.scope, FindingScope("app-1"))
    }

    func testAnInstalledLatestVersionIsNotSuggestedAndResolvesAnActiveOne() {
        let current = UpdateFinding.make(app: app, installed: "1.3.0", latest: "1.3.0", at: now)
        XCTAssertNil(UpdateRule().suggestion(for: current, state: .active))

        let older = UpdateFinding.make(app: app, installed: "2.0.0", latest: "1.3.0", at: now)
        XCTAssertNil(UpdateRule().suggestion(for: older, state: .inactive))
    }

    func testOtherFindingsAreIgnored() {
        let foreign = Finding(moduleID: "dockvac", condition: UpdateFinding.condition, observedAt: now,
                              evidence: ["name": .text("x"), "installed": .text("1"), "latest": .text("2")])
        XCTAssertNil(UpdateRule().suggestion(for: foreign, state: .inactive))
    }

    func testANewerReleaseRefreshesTheSameEpisode() {
        var ledger = SuggestionLedger()
        let scope = UpdateFinding.scope(forAppID: app.id)
        func observe(_ latest: String, at offset: TimeInterval) -> [SuggestionLedger.Event] {
            let date = now.addingTimeInterval(offset)
            let finding = UpdateFinding.make(app: app, installed: "1.2.0", latest: latest, at: date)
            return ledger.apply(.complete(moduleID: UpdateFinding.moduleID, at: date, scopes: [scope],
                                          findings: [finding]), rule: UpdateRule())
        }

        XCTAssertEqual(observe("1.3.0", at: 0), [.opened(finding(scope).key)])
        XCTAssertEqual(observe("1.4.0", at: 60), [.refreshed(finding(scope).key)])
        XCTAssertEqual(ledger.suggestions(at: now.addingTimeInterval(60)).first?.content.title, "Tool 1.4.0 is available")
    }

    private func finding(_ scope: FindingScope) -> Finding {
        Finding(moduleID: UpdateFinding.moduleID, condition: UpdateFinding.condition, scope: scope, observedAt: now)
    }
}
