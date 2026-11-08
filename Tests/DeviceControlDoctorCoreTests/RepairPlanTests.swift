import XCTest
@testable import DoctorCore

final class RepairPlanTests: XCTestCase {
    func testPlanAlwaysTargetsOneBundleAndOnlyChosenServices() throws {
        let plan = try RepairPlan(bundleIdentifier: "com.example.Helper", services: [.postEvent, .accessibility])
        XCTAssertEqual(plan.arguments, [["reset", "Accessibility", "com.example.Helper"], ["reset", "PostEvent", "com.example.Helper"]])
    }
    func testNoBroadOrPathResetsCanBeConstructed() {
        for id in ["", "All", "/Applications/Test.app/Contents/MacOS/Test", "com.example.App --all", "com.example.App\n", "-com.example.App"] {
            XCTAssertThrowsError(try RepairPlan(bundleIdentifier: id, services: [.accessibility]), id)
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
        XCTAssertEqual(GlobalResetService.screenCapture.rawValue, "ScreenCapture")
        XCTAssertEqual(GlobalResetService.audioCapture.rawValue, "AudioCapture")
        XCTAssertEqual(GlobalResetService.screenCapture.settingsAnchor, "Privacy_ScreenCapture")
        XCTAssertEqual(GlobalResetService.audioCapture.settingsAnchor, "Privacy_ScreenCapture")
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
