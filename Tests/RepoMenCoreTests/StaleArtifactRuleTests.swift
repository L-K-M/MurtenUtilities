import XCTest
import MurtenCore
@testable import RepoMenCore

/// The rule is pure: a finding in, at most one suggestion out.
final class StaleArtifactRuleTests: XCTestCase {

    private let rule = StaleArtifactRule(home: "/Users/test")
    private let gigabyte: Int64 = 1_000_000_000

    private func finding(bytes: Int64, folder: String = "/Users/test/dev", count: Int = 12,
                         condition: String = RepoMenRoutes.staleCondition) -> Finding {
        Finding(moduleID: RepoMenRoutes.moduleID, condition: condition, scope: FindingScope(folder),
                observedAt: Date(timeIntervalSince1970: 1_800_000_000),
                evidence: ["bytes": .bytes(bytes), "count": .count(count), "idleDays": .count(30)])
    }

    func testSuggestsAtFiveGigabytes() {
        XCTAssertNil(rule.suggestion(for: finding(bytes: 5 * gigabyte - 1), state: .inactive))
        XCTAssertNotNil(rule.suggestion(for: finding(bytes: 5 * gigabyte), state: .inactive))
    }

    func testStaysActiveUntilBelowFourGigabytes() {
        XCTAssertNotNil(rule.suggestion(for: finding(bytes: 4 * gigabyte), state: .active),
                        "hysteresis: an active suggestion survives a dip below 5 GB")
        XCTAssertNil(rule.suggestion(for: finding(bytes: 4 * gigabyte - 1), state: .active),
                     "below 4 GB the episode resolves")
    }

    func testContentNamesTheFolderAndPromisesNothingIsSelected() throws {
        let content = try XCTUnwrap(rule.suggestion(for: finding(bytes: 6 * gigabyte), state: .inactive))
        XCTAssertTrue(content.title.contains("~/dev"), content.title)
        XCTAssertTrue(content.detail.contains("12 build artifacts"), content.detail)
        XCTAssertTrue(content.detail.contains("over 30 days ago"), content.detail)
        XCTAssertTrue(content.detail.contains("nothing is checked or removed"), content.detail)
    }

    func testRouteReviewsTheFolderAndPassesTheAllowlist() throws {
        let content = try XCTUnwrap(rule.suggestion(for: finding(bytes: 6 * gigabyte), state: .inactive))
        XCTAssertEqual(content.route, ModuleRoute(moduleID: "repomen", action: "review",
                                                  context: ["folder": "/Users/test/dev"]))

        let allowlist = RouteAllowlist(modules: ["repomen"],
                                       actions: ["repomen": ["review": ["folder"], "auto-trash-log": []]])
        XCTAssertEqual(try allowlist.route(from: content.route.url), content.route,
                       "the route survives a notification payload round trip")
    }

    func testOverlongFolderFallsBackToAPlainReview() throws {
        let folder = "/Users/test/" + String(repeating: "deep/", count: 60)
        let content = try XCTUnwrap(rule.suggestion(for: finding(bytes: 6 * gigabyte, folder: folder),
                                                    state: .inactive))
        XCTAssertEqual(content.route, ModuleRoute(moduleID: "repomen", action: "review"))
    }

    func testIgnoresOtherConditionsAndMissingEvidence() {
        XCTAssertNil(rule.suggestion(for: finding(bytes: 9 * gigabyte, condition: "reclaimable"), state: .inactive))
        let bare = Finding(moduleID: "repomen", condition: RepoMenRoutes.staleCondition,
                           scope: FindingScope("/Users/test/dev"), observedAt: Date())
        XCTAssertNil(rule.suggestion(for: bare, state: .inactive))
    }
}
