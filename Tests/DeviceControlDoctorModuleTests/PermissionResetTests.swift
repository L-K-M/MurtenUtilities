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

    func testRecordingCommandsKeepTheirBundleScopeWithoutRequiringClientListing() async throws {
        let runner = FakeProcessRunner()
        runner.withholdListing()
        for service in [ResetService.screenCapture, .audioCapture] {
            runner.respond(to: [SystemTool.tccutil, "reset", service.rawValue, "com.microsoft.teams2"],
                           with: CommandResult(output: "Successfully reset", exitCode: 0))
        }
        let plan = try RepairPlan(bundleIdentifier: "com.microsoft.teams2", services: [.screenCapture, .audioCapture])

        let outcomes = await PermissionReset(runner: runner).apply(plan)

        XCTAssertEqual(runner.calls, [
            [SystemTool.tccutil, "reset", "ScreenCapture", "com.microsoft.teams2"],
            [SystemTool.tccutil, "reset", "AudioCapture", "com.microsoft.teams2"]
        ])
        XCTAssertEqual(outcomes, [.init(service: .screenCapture, failure: nil), .init(service: .audioCapture, failure: nil)])
    }

    func testRecordingErrorsAndTimeoutsPreserveTheSelectedScope() async throws {
        let runner = FakeProcessRunner()
        runner.respond(to: [SystemTool.tccutil, "reset", "ScreenCapture", "com.microsoft.teams2"],
                       with: CommandResult(output: "Reset denied", exitCode: 1))
        runner.respond(to: [SystemTool.tccutil, "reset", "AudioCapture", "com.microsoft.teams2"],
                       with: CommandResult(output: "", exitCode: 0, timedOut: true))
        let plan = try RepairPlan(bundleIdentifier: "com.microsoft.teams2", services: [.screenCapture, .audioCapture])

        let outcomes = await PermissionReset(runner: runner).apply(plan)

        XCTAssertEqual(outcomes.map(\.service), [.screenCapture, .audioCapture])
        XCTAssertEqual(outcomes[0].failure, "Reset denied")
        XCTAssertTrue(outcomes[1].failure?.contains("uncertain") == true)
        XCTAssertTrue(runner.calls.allSatisfy { $0.count == 4 && $0.last == "com.microsoft.teams2" })
    }

    func testTruncatedCommandOutputDoesNotCountAsReportedSuccess() async throws {
        let runner = FakeProcessRunner()
        runner.respond(to: [SystemTool.tccutil, "reset", "Accessibility", "com.example.App"],
                       with: CommandResult(output: "partial output", exitCode: 0, outputTruncated: true))
        let plan = try RepairPlan(bundleIdentifier: "com.example.App", services: [.accessibility])

        let outcomes = await PermissionReset(runner: runner).apply(plan)

        XCTAssertNotNil(outcomes.first?.failure)
        XCTAssertTrue(outcomes.first?.failure?.contains("uncertain") == true)
    }

    func testAnEmptyErrorStillReportsTheExitCode() async throws {
        let runner = FakeProcessRunner()
        runner.respond(to: [SystemTool.tccutil, "reset", "Accessibility", "com.example.App"],
                       with: CommandResult(output: "", exitCode: 1))
        let plan = try RepairPlan(bundleIdentifier: "com.example.App", services: [.accessibility])

        let outcomes = await PermissionReset(runner: runner).apply(plan)

        XCTAssertTrue(outcomes.first?.failure?.contains("exit code 1") == true)
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
