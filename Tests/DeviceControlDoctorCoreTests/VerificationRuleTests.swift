import XCTest
import MurtenCore
@testable import DoctorCore

final class VerificationRuleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let rule = VerificationRule()

    private func app() -> WatchedApp {
        var app = WatchedApp(name: "PopChar", bundleID: "de.ergonis.PopChar", path: "/Applications/PopChar.app", version: "10")
        app.expectedServices = [.accessibility, .postEvent]
        app.identity = .signed()
        return app
    }

    private func finding(_ states: [PermissionService: AuthorizationState],
                         identity: AppIdentity = .signed(), app: WatchedApp? = nil) -> Finding? {
        let app = app ?? self.app()
        let reading = WatchedAppReading(permissions: states.mapValues { AuthorizationResult(state: $0, detail: "fixture") },
                                        identity: identity)
        return VerificationFinding.make(app: app, assessment: VerificationAssessment(app: app, reading: reading), at: now)
    }

    func testNoConcernMakesNoFinding() {
        XCTAssertNil(finding([.accessibility: .granted, .postEvent: .granted]))
    }

    func testFindingIsScopedToTheWatchedApp() throws {
        let app = app()
        let finding = try XCTUnwrap(finding([.accessibility: .denied, .postEvent: .granted], app: app))
        XCTAssertEqual(finding.moduleID, DoctorRoute.moduleID)
        XCTAssertEqual(finding.condition, VerificationFinding.condition)
        XCTAssertEqual(finding.scope, FindingScope(app.id.uuidString))
        XCTAssertEqual(finding.observedAt, now)
    }

    func testDeniedPermissionAsksToVerifyAndOpensReviewOnTheApp() throws {
        let app = app()
        let finding = try XCTUnwrap(finding([.accessibility: .denied, .postEvent: .limited], app: app))
        let content = try XCTUnwrap(rule.suggestion(for: finding, state: .inactive))

        XCTAssertEqual(content.title, "Verify PopChar's permissions again")
        XCTAssertTrue(content.detail.contains("Accessibility, Event generation"), content.detail)
        XCTAssertEqual(content.route, ModuleRoute(moduleID: "devicecontroldoctor", action: "review",
                                                  context: ["app": app.id.uuidString]))
    }

    func testChangedIdentityIsExplainedWithoutClaimingFailure() throws {
        let finding = try XCTUnwrap(finding([.accessibility: .granted, .postEvent: .granted],
                                            identity: .signed(team: "OTHERTEAM1")))
        let content = try XCTUnwrap(rule.suggestion(for: finding, state: .active))
        XCTAssertTrue(content.detail.contains("signing identity changed"), content.detail)
        XCTAssertFalse(content.detail.lowercased().contains("lost"), content.detail)
    }

    func testUnverifiedChangeIsExplained() throws {
        var app = app()
        app.identityChangedAt = now.addingTimeInterval(-3600)
        let finding = try XCTUnwrap(finding([.accessibility: .granted, .postEvent: .granted], app: app))
        let content = try XCTUnwrap(rule.suggestion(for: finding, state: .inactive))
        XCTAssertTrue(content.detail.contains("no passing test"), content.detail)
    }

    func testRouteIsAcceptedByTheSuiteAllowlist() throws {
        let finding = try XCTUnwrap(finding([.accessibility: .denied, .postEvent: .granted]))
        let route = try XCTUnwrap(rule.suggestion(for: finding, state: .inactive)).route
        let allowlist = RouteAllowlist(modules: [DoctorRoute.moduleID], actions: [DoctorRoute.moduleID: DoctorRoute.actions])
        XCTAssertEqual(try allowlist.validate(route), route)
        XCTAssertEqual(try allowlist.route(from: route.url), route)
    }

    func testForeignOrEmptyFindingsMakeNoSuggestion() {
        let scope = FindingScope(UUID().uuidString)
        let foreign = Finding(moduleID: "dockvac", condition: VerificationFinding.condition, scope: scope,
                              observedAt: now, evidence: ["notGranted": .text("Accessibility")])
        let otherCondition = Finding(moduleID: DoctorRoute.moduleID, condition: "other", scope: scope,
                                     observedAt: now, evidence: ["notGranted": .text("Accessibility")])
        let noReasons = Finding(moduleID: DoctorRoute.moduleID, condition: VerificationFinding.condition, scope: scope,
                                observedAt: now, evidence: ["app": .text("PopChar")])
        let badScope = Finding(moduleID: DoctorRoute.moduleID, condition: VerificationFinding.condition,
                               scope: .local, observedAt: now, evidence: ["notGranted": .text("Accessibility")])
        for finding in [foreign, otherCondition, noReasons, badScope] {
            XCTAssertNil(rule.suggestion(for: finding, state: .inactive))
        }
    }

    // MARK: - Route

    func testRouteNamesOneAppAndNothingElse() {
        let id = UUID()
        XCTAssertEqual(DoctorRoute.appID(in: DoctorRoute.review(appID: id)), id)
        XCTAssertNil(DoctorRoute.appID(in: nil))
        XCTAssertNil(DoctorRoute.appID(in: ModuleRoute(moduleID: DoctorRoute.moduleID)))
        XCTAssertNil(DoctorRoute.appID(in: ModuleRoute(moduleID: DoctorRoute.moduleID, action: "review",
                                                       context: ["app": "not-a-uuid"])))
        XCTAssertNil(DoctorRoute.appID(in: ModuleRoute(moduleID: "dockvac", action: "review",
                                                       context: ["app": id.uuidString])))
        XCTAssertEqual(DoctorRoute.actions, ["review": ["app"]])
    }
}
