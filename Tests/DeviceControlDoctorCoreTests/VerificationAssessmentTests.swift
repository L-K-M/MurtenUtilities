import XCTest
import MurtenCore
@testable import DoctorCore

final class VerificationAssessmentTests: XCTestCase {
    private let changedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func app(expecting services: [PermissionService] = [.accessibility],
                     baseline: AppIdentity = .signed()) -> WatchedApp {
        var app = WatchedApp(name: "Example", bundleID: "com.example.App", path: "/Applications/Example.app", version: "1")
        app.expectedServices = services
        app.identity = baseline
        return app
    }

    private func reading(_ states: [PermissionService: AuthorizationState]?,
                         identity: AppIdentity = .signed()) -> WatchedAppReading {
        WatchedAppReading(permissions: states?.mapValues { AuthorizationResult(state: $0, detail: "fixture") },
                          identity: identity)
    }

    // MARK: - Permissions

    func testGrantedExpectedPermissionIsCompleteAndClear() {
        let assessment = VerificationAssessment(app: app(), reading: reading([.accessibility: .granted]))
        XCTAssertFalse(assessment.needsVerification)
        XCTAssertTrue(assessment.isComplete)
    }

    func testDeniedAndLimitedExpectedPermissionsNeedVerification() {
        let assessment = VerificationAssessment(app: app(expecting: [.accessibility, .postEvent, .listenEvent]),
                                                reading: reading([.accessibility: .denied, .postEvent: .granted,
                                                                  .listenEvent: .limited]))
        XCTAssertEqual(assessment.notGranted, [.accessibility, .listenEvent])
        XCTAssertTrue(assessment.needsVerification)
        XCTAssertTrue(assessment.isComplete)
    }

    func testUnexpectedPermissionsAreNotJudged() {
        let assessment = VerificationAssessment(app: app(expecting: []), reading: reading([.accessibility: .denied]))
        XCTAssertFalse(assessment.needsVerification)
        XCTAssertTrue(assessment.isComplete)
    }

    func testUnknownAndUnavailableAreGapsNotDenials() {
        for state in [AuthorizationState.unknown, .unavailable] {
            let assessment = VerificationAssessment(app: app(), reading: reading([.accessibility: state]))
            XCTAssertFalse(assessment.needsVerification, "\(state)")
            XCTAssertFalse(assessment.isComplete, "\(state)")
        }
    }

    func testMissingResultIsAGap() {
        let assessment = VerificationAssessment(app: app(expecting: [.accessibility, .postEvent]),
                                                reading: reading([.accessibility: .granted]))
        XCTAssertFalse(assessment.isComplete)
        XCTAssertFalse(assessment.needsVerification)
    }

    func testUnavailableListingIsAGapForAppsThatExpectPermissions() {
        let assessment = VerificationAssessment(app: app(), reading: reading(nil))
        XCTAssertFalse(assessment.isComplete)
        XCTAssertEqual(assessment.gaps.first?.kind, .toolMissing)
        XCTAssertFalse(assessment.needsVerification)
    }

    func testUnavailableListingDoesNotMatterWithoutExpectedPermissions() {
        let assessment = VerificationAssessment(app: app(expecting: []), reading: reading(nil))
        XCTAssertTrue(assessment.isComplete)
    }

    // MARK: - Identity

    func testChangedIdentityNeedsVerificationEvenWithoutPermissionListing() {
        let assessment = VerificationAssessment(app: app(), reading: reading(nil, identity: .signed(team: "OTHERTEAM1")))
        XCTAssertEqual(assessment.identity, .changed)
        XCTAssertTrue(assessment.needsVerification)
        XCTAssertFalse(assessment.isComplete)
    }

    func testUnfinishedSignatureCheckIsAGap() {
        var unfinished = AppIdentity.signed()
        unfinished.signatureValid = nil
        let assessment = VerificationAssessment(app: app(), reading: reading([.accessibility: .granted], identity: unfinished))
        XCTAssertNil(assessment.identity)
        XCTAssertFalse(assessment.isComplete)
    }

    func testNoBaselineIdentityIsNotAGap() {
        let assessment = VerificationAssessment(app: app(baseline: AppIdentity()),
                                                reading: reading([.accessibility: .granted]))
        XCTAssertNil(assessment.identity)
        XCTAssertTrue(assessment.isComplete)
    }

    func testRecordedChangeStaysUntilAPassingTestFollows() {
        var watched = app()
        watched.identityChangedAt = changedAt
        XCTAssertEqual(VerificationAssessment(app: watched, reading: reading([.accessibility: .granted])).identity,
                       .unverified(since: changedAt))

        watched.lastKnownWorking = changedAt.addingTimeInterval(-60)
        XCTAssertEqual(VerificationAssessment(app: watched, reading: reading([.accessibility: .granted])).identity,
                       .unverified(since: changedAt))

        watched.lastKnownWorking = changedAt.addingTimeInterval(60)
        let verified = VerificationAssessment(app: watched, reading: reading([.accessibility: .granted]))
        XCTAssertNil(verified.identity)
        XCTAssertFalse(verified.needsVerification)
    }

    func testIdentityComparisonMatchesTheStoresRule() {
        let baseline = AppIdentity.signed()
        XCTAssertFalse(AppIdentity.signed().hasChanged(from: baseline))
        XCTAssertTrue(AppIdentity.signed(requirement: "identifier \"other\"").hasChanged(from: baseline))
        XCTAssertTrue(AppIdentity.signed(identifier: "com.example.Other").hasChanged(from: baseline))
        XCTAssertTrue(AppIdentity.signed(team: "OTHERTEAM1").hasChanged(from: baseline))

        var invalid = AppIdentity.signed()
        invalid.signatureValid = false
        XCTAssertTrue(invalid.hasChanged(from: baseline))

        var unchecked = AppIdentity.signed(team: "OTHERTEAM1")
        unchecked.signatureValid = nil
        XCTAssertFalse(unchecked.hasChanged(from: baseline), "an unfinished check proves nothing")
        XCTAssertFalse(AppIdentity.signed(team: "OTHERTEAM1").hasChanged(from: AppIdentity()), "no baseline")
    }
}

extension AppIdentity {
    static func signed(identifier: String = "com.example.App", team: String = "TEAMID1234",
                       requirement: String = "identifier \"com.example.App\" and anchor apple generic") -> AppIdentity {
        var identity = AppIdentity()
        identity.signingIdentifier = identifier
        identity.teamIdentifier = team
        identity.requirement = requirement
        identity.signatureValid = true
        identity.signatureDetail = "valid on disk"
        return identity
    }
}
