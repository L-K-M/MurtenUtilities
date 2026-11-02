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
