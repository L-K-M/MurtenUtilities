import XCTest
import DoctorCore
@testable import DeviceControlDoctorModule

/// The reset path against the fake process boundary: exactly the confirmed
/// plan runs, and nothing short of a clean exit counts as success.
final class PermissionResetTests: XCTestCase {
    func testRunsOneBundleScopedResetPerSelectedService() async throws {
        let runner = FakeProcessRunner()
        runner.respond(to: [SystemTool.tccutil, "reset", "Accessibility", "com.example.App"], with: CommandResult(output: "", exitCode: 0))
        runner.respond(to: [SystemTool.tccutil, "reset", "PostEvent", "com.example.App"], with: CommandResult(output: "", exitCode: 0))
        let plan = try RepairPlan(bundleIdentifier: "com.example.App", services: [.postEvent, .accessibility])

        let outcomes = await PermissionReset(runner: runner).apply(plan)

        XCTAssertEqual(runner.calls, [["/usr/bin/tccutil", "reset", "Accessibility", "com.example.App"],
                                      ["/usr/bin/tccutil", "reset", "PostEvent", "com.example.App"]])
        XCTAssertEqual(outcomes, [.init(service: .accessibility, failure: nil), .init(service: .postEvent, failure: nil)])
    }

    func testTimeoutsAndErrorsAreNeverReportedAsSuccess() async throws {
        let runner = FakeProcessRunner()
        runner.respond(to: [SystemTool.tccutil, "reset", "Accessibility", "com.example.App"],
                       with: CommandResult(output: "", exitCode: 0, timedOut: true))
        runner.respond(to: [SystemTool.tccutil, "reset", "ListenEvent", "com.example.App"],
                       with: CommandResult(output: "tccutil: Failed to reset ListenEvent", exitCode: 1))
        let plan = try RepairPlan(bundleIdentifier: "com.example.App", services: [.accessibility, .listenEvent])

        let outcomes = await PermissionReset(runner: runner).apply(plan)

        XCTAssertEqual(outcomes.map(\.service), [.accessibility, .listenEvent])
        XCTAssertTrue(outcomes[0].failure?.contains("timed out") == true)
        XCTAssertEqual(outcomes[1].failure, "tccutil: Failed to reset ListenEvent")
    }
}
