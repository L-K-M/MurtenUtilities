import XCTest
@testable import DoctorCore

final class RepairPlanTests: XCTestCase {
    func testPlanAlwaysTargetsOneBundleAndOnlyChosenServices() throws {
        let plan = try RepairPlan(bundleIdentifier: "com.example.Helper", services: [.postEvent, .accessibility])
        XCTAssertEqual(plan.arguments, [["reset", "Accessibility", "com.example.Helper"], ["reset", "PostEvent", "com.example.Helper"]])
    }
    func testRecordingPlanTargetsTeamsWithBothSelectedServices() throws {
        let plan = try RepairPlan(bundleIdentifier: "com.microsoft.teams2", services: [.audioCapture, .screenCapture])

        XCTAssertEqual(plan.arguments, [
            ["reset", "ScreenCapture", "com.microsoft.teams2"],
            ["reset", "AudioCapture", "com.microsoft.teams2"]
        ])
    }

    func testEveryResettableServiceCanBeScopedToOneBundle() throws {
        for service in ResetService.allCases {
            let plan = try RepairPlan(bundleIdentifier: "com.microsoft.teams2", services: [service])
            XCTAssertEqual(plan.arguments, [["reset", service.rawValue, "com.microsoft.teams2"]])
        }
    }

    func testWatchListDefaultsDoNotSelectRecordingResets() {
        XCTAssertEqual(PermissionService.allCases.map { ResetService($0) }, [.accessibility, .postEvent, .listenEvent])
    }

    func testNoBroadOrPathResetsCanBeConstructed() {
        for id in ["", "All", "/Applications/Test.app/Contents/MacOS/Test", "com.example.App --all", "com.example.App\n", "-com.example.App"] {
            XCTAssertThrowsError(try RepairPlan(bundleIdentifier: id, services: Set(ResetService.allCases)), id)
        }
        XCTAssertThrowsError(try RepairPlan(bundleIdentifier: "com.example.App", services: []))
    }
    func testGlobalPlanResetsEveryManagedServiceWithoutAClientIdentifier() {
        let plan = GlobalRepairPlan()

        XCTAssertEqual(plan.services, [.accessibility, .postEvent, .listenEvent, .screenCapture, .audioCapture])
        XCTAssertEqual(plan.arguments, [
            ["reset", "Accessibility"],
            ["reset", "PostEvent"],
            ["reset", "ListenEvent"],
            ["reset", "ScreenCapture"],
            ["reset", "AudioCapture"]
        ])
    }
    func testGlobalPlanIncludesRecordingWithoutExpandingTheWatchList() {
        XCTAssertEqual(GlobalRepairPlan().services.map(\.rawValue), [
            "Accessibility", "PostEvent", "ListenEvent", "ScreenCapture", "AudioCapture"
        ])
        XCTAssertEqual(PermissionService.allCases.map(\.rawValue), [
            "Accessibility", "PostEvent", "ListenEvent"
        ], "recording recovery must not add unimplemented functional tests or watcher checks")
    }

    func testRecordingServicesUseTheirCanonicalNamesAndSharedSettingsPane() {
        XCTAssertEqual(ResetService.screenCapture.rawValue, "ScreenCapture")
        XCTAssertEqual(ResetService.audioCapture.rawValue, "AudioCapture")
        XCTAssertEqual(ResetService.screenCapture.settingsAnchor, "Privacy_ScreenCapture")
        XCTAssertEqual(ResetService.audioCapture.settingsAnchor, "Privacy_ScreenCapture")
    }

    func testUnknownIsNotTreatedAsDenied() {
        var app = WatchedApp(name: "Example", bundleID: "com.example.App", path: "/Applications/Example.app", version: "1")
        app.expectedServices = [.accessibility]
        app.readings = [PermissionReading(service: .accessibility, result: .init(state: .unknown, detail: "Timed out"))]
        XCTAssertFalse(app.hasDeniedExpectedPermission)
        XCTAssertEqual(app.summary, "Needs verification")
    }
    func testGrantIsNotAFunctionalPass() {
        var app = WatchedApp(name: "Example", bundleID: "com.example.App", path: "/Applications/Example.app", version: "1")
        app.expectedServices = [.accessibility, .postEvent]
        app.readings = [PermissionService.accessibility, .postEvent].map { PermissionReading(service: $0, result: .init(state: .granted, detail: "OS report")) }
        XCTAssertEqual(app.summary, "Granted · untested")
        XCTAssertNil(app.lastKnownWorking)
    }
}
