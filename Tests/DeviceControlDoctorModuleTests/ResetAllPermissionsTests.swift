import XCTest
import DoctorCore
@testable import DeviceControlDoctorModule

@MainActor
final class ResetAllPermissionsTests: XCTestCase {
    func testQuitsEveryRunningAffectedAppBeforeBroadResets() async {
        let runner = configuredRunner()
        let first = AffectedProcess(processIdentifier: 101, name: "First", executablePath: "/Applications/First.app/Contents/MacOS/First", canRequestTermination: true)
        let second = AffectedProcess(processIdentifier: 202, name: "Second", executablePath: "/Applications/Second.app/Contents/MacOS/Second", canRequestTermination: true)
        let lifecycle = FakeApplicationLifecycle(running: [first, second], runner: runner)
        let reset = makeReset(runner: runner, lifecycle: lifecycle)

        let result = await reset.apply()

        XCTAssertTrue(result.succeeded)
        XCTAssertNil(result.failure)
        XCTAssertEqual(lifecycle.terminationRequests, [[first, second]])
        XCTAssertFalse(lifecycle.resetHadStartedWhenTerminationWasRequested)
        XCTAssertEqual(resetCalls(runner), [
            [SystemTool.tccutil, "reset", "Accessibility"],
            [SystemTool.tccutil, "reset", "PostEvent"],
            [SystemTool.tccutil, "reset", "ListenEvent"]
        ])
    }

    func testRunsNoResetWhenAnAffectedAppWillNotQuit() async {
        let runner = configuredRunner()
        let process = AffectedProcess(processIdentifier: 101, name: "Stubborn", executablePath: "/Applications/Stubborn.app/Contents/MacOS/Stubborn", canRequestTermination: true)
        let lifecycle = FakeApplicationLifecycle(running: [process], runner: runner)
        lifecycle.refusesTermination = true

        let result = await makeReset(runner: runner, lifecycle: lifecycle).apply()

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.failure?.contains("Stubborn") == true)
        XCTAssertTrue(resetCalls(runner).isEmpty, "no permission may be cleared while an affected app remains open")
    }

    func testStopsRemainingResetsWhenAnAffectedAppRelaunches() async {
        let runner = configuredRunner()
        let relaunched = AffectedProcess(processIdentifier: 303, name: "Relaunched", executablePath: "/Applications/Relaunched.app/Contents/MacOS/Relaunched", canRequestTermination: true)
        let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)
        // Stable preflight, scope recheck, then pre-command checks. The app
        // appears before the second mutation.
        lifecycle.snapshots = [[], [], [], [], [relaunched]]

        let result = await makeReset(runner: runner, lifecycle: lifecycle).apply()

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.failure?.contains("Relaunched") == true)
        XCTAssertEqual(resetCalls(runner), [[SystemTool.tccutil, "reset", "Accessibility"]])
        XCTAssertTrue(lifecycle.matchedClients.last?.contains("com.example.First") == true,
                      "clients whose earlier record was reset must stay in every later safety check")
    }

    func testRelaunchDuringTheFinalScopeReadRunsNoReset() async {
        let runner = configuredRunner()
        let relaunched = AffectedProcess(processIdentifier: 304, name: "Relaunched",
                                         executablePath: "/Applications/Relaunched.app/Contents/MacOS/Relaunched",
                                         canRequestTermination: true)
        let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)
        // Initial and post-quit checks are empty. The first pre-command
        // inventory is empty, but the app appears while the bracketing client
        // list is read and is caught by the final inventory.
        lifecycle.snapshots = [[], [], [], [relaunched]]

        let result = await makeReset(runner: runner, lifecycle: lifecycle).apply()

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.failure?.contains("Relaunched") == true)
        XCTAssertTrue(resetCalls(runner).isEmpty)
    }

    func testFailsClosedWhenClientListingIsUnavailable() async {
        let runner = FakeProcessRunner()
        runner.withholdListing()
        let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)

        let result = await makeReset(runner: runner, lifecycle: lifecycle).apply()

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.failure?.contains("client list") == true)
        XCTAssertTrue(lifecycle.terminationRequests.isEmpty)
        XCTAssertTrue(resetCalls(runner).isEmpty)
    }

    func testFailsClosedWhenAClientListContainsAnUnknownRecord() async {
        let runner = configuredRunner()
        runner.respond(to: [SystemTool.tccutil, "list", "-s", "Accessibility"],
                       with: CommandResult(output: "com.example.First\nunrecognized client format", exitCode: 0))
        let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)

        let result = await makeReset(runner: runner, lifecycle: lifecycle).apply()

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.failure?.contains("unrecognized record") == true)
        XCTAssertTrue(resetCalls(runner).isEmpty,
                      "a partial client inventory must never authorize a broad reset")
    }

    func testListTimeoutRunsNoReset() async {
        let runner = configuredRunner()
        runner.respond(to: [SystemTool.tccutil, "list", "-s", "Accessibility"],
                       with: CommandResult(output: "", exitCode: -1, timedOut: true))
        let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)

        let result = await makeReset(runner: runner, lifecycle: lifecycle).apply()

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.failure?.contains("timed out") == true)
        XCTAssertTrue(resetCalls(runner).isEmpty)
    }

    func testTruncatedClientListRunsNoReset() async {
        let runner = configuredRunner()
        runner.respond(to: [SystemTool.tccutil, "list", "-s", "Accessibility"],
                       with: CommandResult(output: "com.example.First", exitCode: 0,
                                           outputTruncated: true))
        let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)

        let result = await makeReset(runner: runner, lifecycle: lifecycle).apply()

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.failure?.contains("truncated") == true)
        XCTAssertTrue(resetCalls(runner).isEmpty,
                      "a syntactically valid retained prefix is not a complete inventory")
    }

    func testResetTimeoutStopsBeforeAnyOtherService() async {
        let runner = configuredRunner()
        runner.respond(to: [SystemTool.tccutil, "reset", "Accessibility"],
                       with: CommandResult(output: "", exitCode: -1, timedOut: true))
        let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)

        let result = await makeReset(runner: runner, lifecycle: lifecycle).apply()

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.failure?.contains("outcome is uncertain") == true)
        XCTAssertEqual(resetCalls(runner), [[SystemTool.tccutil, "reset", "Accessibility"]])
    }

    func testSuccessfulResetWithFailedVerificationIsNotReportedAsCompleted() async {
        let runner = configuredRunner()
        let listed = CommandResult(output: "com.example.First\ncom.example.Second", exitCode: 0)
        runner.respond(to: [SystemTool.tccutil, "list", "-s", "Accessibility"], with: [
            listed, listed, listed, listed, listed,
            CommandResult(output: "", exitCode: -1, timedOut: true)
        ])
        let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)

        let result = await makeReset(runner: runner, lifecycle: lifecycle).apply()

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.outcomes.count, 1)
        XCTAssertNotNil(result.outcomes[0].failure,
                        "a reset is not complete until its empty postcondition is verified")
        XCTAssertTrue(result.failure?.contains("timed out") == true)
        XCTAssertEqual(resetCalls(runner), [[SystemTool.tccutil, "reset", "Accessibility"]])
    }

    func testStopsWhenAResetDoesNotClearItsServiceRecords() async {
        let runner = configuredRunner(clearsAfterReset: false)
        let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)

        let result = await makeReset(runner: runner, lifecycle: lifecycle).apply()

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.failure?.contains("not empty after reset") == true)
        XCTAssertEqual(resetCalls(runner), [[SystemTool.tccutil, "reset", "Accessibility"]])
    }

    func testCancellationBeforeInventoryRunsNoReset() async {
        let runner = configuredRunner()
        runner.cancelCallingTask()
        let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)

        let result = await makeReset(runner: runner, lifecycle: lifecycle).apply()

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.failure?.contains("cancelled") == true)
        XCTAssertTrue(resetCalls(runner).isEmpty)
    }

    func testInspectionReportsEveryRecordedClientAndRunningProcess() async throws {
        let runner = configuredRunner()
        let process = AffectedProcess(processIdentifier: 101, name: "First", executablePath: "/Applications/First.app/Contents/MacOS/First", canRequestTermination: true)
        let lifecycle = FakeApplicationLifecycle(running: [process], runner: runner)

        let preparation = try await makeReset(runner: runner, lifecycle: lifecycle).inspect()

        XCTAssertEqual(preparation.clients, ["com.example.First", "com.example.Second"])
        XCTAssertEqual(preparation.runningProcesses, [process])
    }

    private func configuredRunner(clearsAfterReset: Bool = true) -> FakeProcessRunner {
        let runner = FakeProcessRunner()
        if clearsAfterReset { runner.clearListedServiceAfterReset() }
        runner.offerListing()
        runner.respond(to: [SystemTool.tccutil, "list", "-s", "Accessibility"],
                       with: CommandResult(output: "com.example.First\ncom.example.Second", exitCode: 0))
        runner.respond(to: [SystemTool.tccutil, "list", "-s", "PostEvent"],
                       with: CommandResult(output: "com.example.First", exitCode: 0))
        runner.respond(to: [SystemTool.tccutil, "list", "-s", "ListenEvent"],
                       with: CommandResult(output: "com.example.Second", exitCode: 0))
        for service in PermissionService.allCases {
            runner.respond(to: [SystemTool.tccutil, "reset", service.rawValue], with: CommandResult(output: "", exitCode: 0))
        }
        return runner
    }

    private func makeReset(runner: FakeProcessRunner, lifecycle: FakeApplicationLifecycle) -> ResetAllPermissions {
        ResetAllPermissions(runner: runner, lifecycle: lifecycle,
                            timing: .init(pollNanoseconds: 0, stableSamples: 1, maximumPolls: 3))
    }

    private func resetCalls(_ runner: FakeProcessRunner) -> [[String]] {
        runner.calls.filter { $0.count >= 2 && $0[0] == SystemTool.tccutil && $0[1] == "reset" }
    }
}

@MainActor
private final class FakeApplicationLifecycle: ApplicationLifecycleManaging {
    var running: [AffectedProcess]
    var snapshots: [[AffectedProcess]] = []
    var refusesTermination = false
    var terminationRequests: [[AffectedProcess]] = []
    var matchedClients: [Set<String>] = []
    var resetHadStartedWhenTerminationWasRequested = false
    private let runner: FakeProcessRunner

    init(running: [AffectedProcess], runner: FakeProcessRunner) {
        self.running = running
        self.runner = runner
    }

    func runningProcesses(matching clients: Set<String>) async throws -> [AffectedProcess] {
        matchedClients.append(clients)
        if !snapshots.isEmpty { return snapshots.removeFirst() }
        return running
    }

    func requestTermination(of processes: [AffectedProcess]) {
        resetHadStartedWhenTerminationWasRequested = runner.ranReset
        terminationRequests.append(processes)
        if !refusesTermination { running.removeAll() }
    }
}
