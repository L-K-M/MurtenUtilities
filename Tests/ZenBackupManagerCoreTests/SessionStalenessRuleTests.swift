import XCTest
import MurtenCore
@testable import ZenBackupManagerCore

final class SessionStalenessRuleTests: XCTestCase {
    private let rule = SessionStalenessRule()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let profile = ZenProfile(name: "Default (release)",
                                     directory: URL(fileURLWithPath: "/Users/me/Library/Application Support/zen/Profiles/abc.Default (release)"),
                                     isDefault: true)
    private let day: TimeInterval = 24 * 3600

    private func finding(age: TimeInterval, for profile: ZenProfile? = nil) -> Finding {
        SessionStalenessRule.finding(for: profile ?? self.profile, newestSnapshot: now.addingTimeInterval(-age), observedAt: now)
    }

    func testFindingIsScopedByProfileAndCarriesTheAge() {
        let result = finding(age: 3 * day)
        XCTAssertEqual(result.moduleID, ZenBackupRoute.moduleID)
        XCTAssertEqual(result.condition, SessionStalenessRule.condition)
        XCTAssertEqual(result.scope, FindingScope(profile.id))
        XCTAssertEqual(result.seconds("age"), 3 * day)
        XCTAssertEqual(result.date("newestSnapshot"), now.addingTimeInterval(-3 * day))
    }

    func testSnapshotDatedInTheFutureCountsAsFresh() {
        XCTAssertEqual(finding(age: -day).seconds("age"), 0)
    }

    func testUnderAWeekSuggestsNothing() {
        XCTAssertNil(rule.suggestion(for: finding(age: 7 * day - 1), state: .inactive))
        XCTAssertNil(rule.suggestion(for: finding(age: 7 * day - 1), state: .active), "a save resolves the episode")
    }

    func testAWeekSaysZenHasNotSavedNotThatABackupIsOverdue() throws {
        let content = try XCTUnwrap(rule.suggestion(for: finding(age: 7 * day), state: .inactive))
        XCTAssertEqual(content.title, "Zen has not saved a session in 7 days")
        XCTAssertTrue(content.detail.contains("“Default (release)”"))
        XCTAssertTrue(content.detail.contains("crashing"))
        for word in ["overdue", "backup is due", "back up now"] {
            XCTAssertFalse((content.title + content.detail).lowercased().contains(word), word)
        }
    }

    func testDaysAreWholeDaysElapsed() throws {
        let content = try XCTUnwrap(rule.suggestion(for: finding(age: 9.9 * day), state: .active))
        XCTAssertEqual(content.title, "Zen has not saved a session in 9 days")
    }

    func testRouteOpensTheTimelineOnTheProfileAndPassesTheAllowlist() throws {
        let content = try XCTUnwrap(rule.suggestion(for: finding(age: 8 * day), state: .inactive))
        XCTAssertEqual(content.route, ModuleRoute(moduleID: ZenBackupRoute.moduleID, action: ZenBackupRoute.timelineAction,
                                                  context: [ZenBackupRoute.profileKey: profile.id]))

        let allowlist = RouteAllowlist(modules: [ZenBackupRoute.moduleID],
                                       actions: [ZenBackupRoute.moduleID: [ZenBackupRoute.timelineAction: [ZenBackupRoute.profileKey]]])
        XCTAssertEqual(try allowlist.validate(content.route), content.route)
        XCTAssertEqual(try allowlist.route(from: content.route.url), content.route)
    }

    func testOverlongProfilePathOpensTheTimelineWithoutContext() throws {
        let deep = ZenProfile(name: "Deep", directory: URL(fileURLWithPath: "/" + String(repeating: "a/", count: 200)), isDefault: false)
        let content = try XCTUnwrap(rule.suggestion(for: finding(age: 8 * day, for: deep), state: .inactive))
        XCTAssertEqual(content.route, ModuleRoute(moduleID: ZenBackupRoute.moduleID, action: ZenBackupRoute.timelineAction))
    }

    func testOtherConditionsAreIgnored() {
        let other = Finding(moduleID: ZenBackupRoute.moduleID, condition: "something-else", observedAt: now,
                            evidence: ["age": .seconds(30 * day)])
        XCTAssertNil(rule.suggestion(for: other, state: .inactive))
    }
}
