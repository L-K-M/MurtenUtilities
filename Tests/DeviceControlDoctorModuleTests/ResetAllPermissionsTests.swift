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
            [SystemTool.tccutil, "reset", "ListenEvent"],
            [SystemTool.tccutil, "reset", "ScreenCapture"],
            [SystemTool.tccutil, "reset", "AudioCapture"]
        ])
    }

    func testRunsNoResetWhenAnAffectedAppWillNotQuit() async {
        let runner = configuredRunner()
        let process = AffectedProcess(processIdentifier: 101, name: "Stubborn", executablePath: "/Applications/Stubborn.app/Contents/MacOS/Stubborn", canRequestTermination: true)
        let lifecycle = FakeApplicationLifecycle(running: [process], runner: runner)
        lifecycle.refusesTermination = true

        let result = await makeReset(runner: runner, lifecycle: lifecycle).apply()

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.failure?.contains("1 affected process is still running") == true)
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
        XCTAssertTrue(result.failure?.contains("1 affected process is still running") == true)
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
        XCTAssertTrue(result.failure?.contains("1 affected process is still running") == true)
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

    func testInspectionFailureSaysNothingWasReset() async {
        let runner = configuredRunner()
        let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)
        lifecycle.error = FakeApplicationLifecycle.Failure.inventory

        do {
            _ = try await makeReset(runner: runner, lifecycle: lifecycle).inspect()
            XCTFail("an inventory failure must disable Reset All")
        } catch {
            XCTAssertTrue(error.localizedDescription.hasSuffix("No permissions were reset."),
                          error.localizedDescription)
        }
        XCTAssertTrue(resetCalls(runner).isEmpty)
    }

    func testFailureBeforeTheFirstResetSaysNothingWasReset() async {
        let runner = configuredRunner()
        let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)
        lifecycle.error = FakeApplicationLifecycle.Failure.inventory

        let result = await makeReset(runner: runner, lifecycle: lifecycle).apply()

        XCTAssertTrue(result.outcomes.isEmpty)
        XCTAssertTrue(result.failure?.hasSuffix("No permissions were reset.") == true, result.failure ?? "")
    }

    func testFailureAfterAResetSaysNoFurtherPermissionsWereReset() async {
        let runner = configuredRunner()
        let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)
        lifecycle.failsAfterFirstReset = true

        let result = await makeReset(runner: runner, lifecycle: lifecycle).apply()

        XCTAssertEqual(resetCalls(runner), [[SystemTool.tccutil, "reset", "Accessibility"]])
        XCTAssertTrue(result.failure?.hasSuffix("No further permissions were reset.") == true, result.failure ?? "")
    }

    func testAcknowledgedOverrideResetsWithoutQuittingRunningProcesses() async {
        let runner = configuredRunner()
        let process = AffectedProcess(processIdentifier: 101, name: "Stubborn helper",
                                      executablePath: "/fixture/helper", canRequestTermination: true)
        let lifecycle = FakeApplicationLifecycle(running: [process], runner: runner)
        lifecycle.refusesTermination = true

        let result = await makeReset(runner: runner, lifecycle: lifecycle).apply(policy: .allowRunning)

        XCTAssertTrue(result.succeeded, result.failure ?? "")
        XCTAssertEqual(resetCalls(runner).count, 5)
        XCTAssertTrue(lifecycle.terminationRequests.isEmpty,
                      "override resets without automatically quitting or force-quitting apps")
        XCTAssertFalse(lifecycle.matchedClients.isEmpty, "override must still inspect processes")
    }

    func testQuittingProgressShowsProcessesThatRemainAfterTheQuitRequest() async {
        let runner = configuredRunner()
        let process = AffectedProcess(processIdentifier: 101, name: "Stubborn helper",
                                      executablePath: "/fixture/helper", canRequestTermination: true)
        let lifecycle = FakeApplicationLifecycle(running: [process], runner: runner)
        lifecycle.refusesTermination = true
        var observed: [[AffectedProcess]] = []
        var requested: [[AffectedProcess]] = []

        let result = await makeReset(runner: runner, lifecycle: lifecycle).apply { update in
            switch update {
            case .processes(let processes): observed.append(processes)
            case .quitRequested(let processes): requested.append(processes)
            default: break
            }
        }

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(observed.last, [process], "the UI needs the current blocker, not just a failure string")
        XCTAssertEqual(requested.first, [process])
        XCTAssertTrue(resetCalls(runner).isEmpty)
    }

    func testOverrideCannotBypassFailedInventoryOrUnverifiableReset() async {
        let runner = configuredRunner()
        let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)
        lifecycle.error = .inventory
        let denied = await makeReset(runner: runner, lifecycle: lifecycle).apply(policy: .allowRunning)
        XCTAssertFalse(denied.succeeded)
        XCTAssertTrue(resetCalls(runner).isEmpty)

        let unchangedRunner = configuredRunner(clearsAfterReset: false)
        let unchanged = await makeReset(runner: unchangedRunner,
                                       lifecycle: FakeApplicationLifecycle(running: [], runner: unchangedRunner))
            .apply(policy: .allowRunning)
        XCTAssertFalse(unchanged.succeeded)
        XCTAssertEqual(resetCalls(unchangedRunner).count, 1)
        XCTAssertTrue(unchanged.failure?.contains("not empty after reset") == true)
    }

    func testOverrideStillRejectsUnavailableOrIncompleteClientLists() async {
        let failures = [
            CommandResult(output: "unrecognized record", exitCode: 0),
            CommandResult(output: "", exitCode: -1, timedOut: true),
            CommandResult(output: "com.example.App", exitCode: 0, outputTruncated: true),
            CommandResult(output: "not permitted", exitCode: 1)
        ]
        for command in failures {
            let runner = configuredRunner()
            runner.respond(to: [SystemTool.tccutil, "list", "-s", "Accessibility"], with: command)
            let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)
            let result = await makeReset(runner: runner, lifecycle: lifecycle).apply(policy: .allowRunning)
            XCTAssertFalse(result.succeeded)
            XCTAssertTrue(resetCalls(runner).isEmpty)
            XCTAssertTrue(lifecycle.terminationRequests.isEmpty)
        }
        let runner = configuredRunner()
        runner.withholdListing()
        let unavailable = await makeReset(runner: runner,
                                         lifecycle: FakeApplicationLifecycle(running: [], runner: runner))
            .apply(policy: .allowRunning)
        XCTAssertFalse(unavailable.succeeded)
        XCTAssertTrue(resetCalls(runner).isEmpty)
    }

    func testOverrideStillStopsWhenInventoryFailsAfterOneServiceReset() async {
        let runner = configuredRunner()
        let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)
        lifecycle.failsAfterFirstReset = true

        let result = await makeReset(runner: runner, lifecycle: lifecycle).apply(policy: .allowRunning)

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(resetCalls(runner).count, 1)
        XCTAssertTrue(result.failure?.hasSuffix("No further permissions were reset.") == true)
    }

    func testRecentlyExitedProcessesAreNotReportedAsStillRunning() async {
        let runner = configuredRunner()
        let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)
        let reset = ResetAllPermissions(runner: runner, lifecycle: lifecycle,
                                       timing: .init(pollNanoseconds: 0, stableSamples: 3, maximumPolls: 2))

        let result = await reset.apply()

        XCTAssertTrue(result.failure?.contains("not stayed closed long enough") == true)
        XCTAssertFalse(result.failure?.contains("still running") == true)
        XCTAssertTrue(resetCalls(runner).isEmpty)
    }

    func testInspectionIncludesClientsWhoseRecordsWereAlreadyReset() async throws {
        let runner = configuredRunner()
        let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)

        let preparation = try await makeReset(runner: runner, lifecycle: lifecycle)
            .inspect(including: ["com.example.AlreadyReset"])

        XCTAssertTrue(preparation.clients.contains("com.example.AlreadyReset"))
        XCTAssertTrue(lifecycle.matchedClients.last?.contains("com.example.AlreadyReset") == true)
    }

    func testRetryKeepsEarlierClientsInEveryProcessCheck() async {
        let runner = configuredRunner()
        let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)

        let result = await makeReset(runner: runner, lifecycle: lifecycle)
            .apply(including: ["com.example.AlreadyReset"])

        XCTAssertTrue(result.succeeded, result.failure ?? "")
        XCTAssertFalse(lifecycle.matchedClients.isEmpty)
        XCTAssertTrue(lifecycle.matchedClients.allSatisfy { $0.contains("com.example.AlreadyReset") })
    }

    func testCancellationBeforeOverridePreflightDoesNotStartAnotherInventory() async {
        let runner = configuredRunner()
        let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)
        let reset = makeReset(runner: runner, lifecycle: lifecycle)
        let result = await Task {
            await reset.apply(policy: .allowRunning) { update in
                if case .clients = update { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }.value

        XCTAssertTrue(result.failure?.contains("cancelled") == true)
        XCTAssertTrue(lifecycle.matchedClients.isEmpty)
        XCTAssertTrue(resetCalls(runner).isEmpty)
    }

    func testZeroPollBudgetDoesNotClaimThatZeroProcessesAreStillRunning() async {
        let runner = configuredRunner()
        let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)
        let reset = ResetAllPermissions(runner: runner, lifecycle: lifecycle,
                                       timing: .init(pollNanoseconds: 0, stableSamples: 1, maximumPolls: 0))

        let result = await reset.apply()

        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(result.failure?.contains("0 affected processes are still running") == true)
        XCTAssertTrue(resetCalls(runner).isEmpty)
    }

    func testInspectionIncludesScreenAndAudioOnlyClients() async throws {
        let runner = configuredRunner()
        runner.respond(to: [SystemTool.tccutil, "list", "-s", "ScreenCapture"],
                       with: CommandResult(output: "com.example.ScreenRecorder", exitCode: 0))
        runner.respond(to: [SystemTool.tccutil, "list", "-s", "AudioCapture"],
                       with: CommandResult(output: "com.example.AudioRecorder", exitCode: 0))
        let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)

        let preparation = try await makeReset(runner: runner, lifecycle: lifecycle).inspect()

        XCTAssertTrue(preparation.clients.contains("com.example.ScreenRecorder"))
        XCTAssertTrue(preparation.clients.contains("com.example.AudioRecorder"))
        XCTAssertTrue(lifecycle.matchedClients.last?.contains("com.example.ScreenRecorder") == true)
        XCTAssertTrue(lifecycle.matchedClients.last?.contains("com.example.AudioRecorder") == true)
        XCTAssertTrue(resetCalls(runner).isEmpty)
    }

    func testResetAllResetsScreenAndSystemAudioServicesToo() async {
        let runner = configuredRunner()
        for service in ["ScreenCapture", "AudioCapture"] {
            runner.respond(to: [SystemTool.tccutil, "list", "-s", service],
                           with: CommandResult(output: "com.example.Recorder", exitCode: 0))
            runner.respond(to: [SystemTool.tccutil, "reset", service],
                           with: CommandResult(output: "", exitCode: 0))
        }
        let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)

        let result = await makeReset(runner: runner, lifecycle: lifecycle).apply()

        XCTAssertTrue(result.succeeded, result.failure ?? "")
        XCTAssertEqual(resetCalls(runner).suffix(2).map { $0 }, [
            [SystemTool.tccutil, "reset", "ScreenCapture"],
            [SystemTool.tccutil, "reset", "AudioCapture"]
        ])
        XCTAssertEqual(result.outcomes.count, 5)
    }

    func testRecordingOnlyClientsAreCheckedBeforeResetAndOverrideRemainsExplicit() async {
        for service in [GlobalResetService.screenCapture, .audioCapture] {
            let runner = configuredRunner()
            for permission in PermissionService.allCases {
                runner.respond(to: [SystemTool.tccutil, "list", "-s", permission.rawValue],
                               with: CommandResult(output: "", exitCode: 0))
            }
            runner.respond(to: [SystemTool.tccutil, "list", "-s", service.rawValue],
                           with: CommandResult(output: "com.example.RecordingOnly", exitCode: 0))
            let process = AffectedProcess(processIdentifier: 301, name: "Recorder",
                                          executablePath: "/fixture/recorder", canRequestTermination: true)
            let lifecycle = FakeApplicationLifecycle(running: [process], runner: runner)
            lifecycle.refusesTermination = true
            let reset = makeReset(runner: runner, lifecycle: lifecycle)

            let blocked = await reset.apply()

            XCTAssertFalse(blocked.succeeded)
            XCTAssertTrue(resetCalls(runner).isEmpty)
            XCTAssertTrue(lifecycle.matchedClients.last?.contains("com.example.RecordingOnly") == true)
            let quitRequests = lifecycle.terminationRequests.count

            let acknowledged = await reset.apply(policy: .allowRunning)

            XCTAssertTrue(acknowledged.succeeded, acknowledged.failure ?? "")
            XCTAssertEqual(resetCalls(runner).count, 5)
            XCTAssertEqual(lifecycle.terminationRequests.count, quitRequests)
        }
    }

    func testUnverifiableRecordingClientListsBlockEvenTheOverrideBeforeAnyReset() async {
        let failures = [
            CommandResult(output: "Unsupported service", exitCode: 1),
            CommandResult(output: "", exitCode: -1, timedOut: true),
            CommandResult(output: "com.example.Recorder", exitCode: 0, outputTruncated: true)
        ]
        for service in [GlobalResetService.screenCapture, .audioCapture] {
            for failure in failures {
                let runner = configuredRunner()
                runner.respond(to: [SystemTool.tccutil, "list", "-s", service.rawValue], with: failure)
                let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)

                let result = await makeReset(runner: runner, lifecycle: lifecycle).apply(policy: .allowRunning)

                XCTAssertFalse(result.succeeded)
                XCTAssertTrue(result.failure?.contains(service.title) == true)
                XCTAssertTrue(resetCalls(runner).isEmpty)
                XCTAssertTrue(lifecycle.terminationRequests.isEmpty)
            }
        }
    }

    func testRecordingServicesRequireTheirOwnVerifiedEmptyPostconditions() async {
        for (service, attemptedCount) in [(GlobalResetService.screenCapture, 4), (.audioCapture, 5)] {
            let runner = configuredRunner(clearsAfterReset: false)
            for permission in GlobalRepairPlan().services {
                runner.respond(to: [SystemTool.tccutil, "list", "-s", permission.rawValue],
                               with: CommandResult(output: "", exitCode: 0))
            }
            runner.respond(to: [SystemTool.tccutil, "list", "-s", service.rawValue],
                           with: CommandResult(output: "com.example.Recorder", exitCode: 0))
            let lifecycle = FakeApplicationLifecycle(running: [], runner: runner)

            let result = await makeReset(runner: runner, lifecycle: lifecycle).apply()

            XCTAssertFalse(result.succeeded)
            XCTAssertEqual(resetCalls(runner).count, attemptedCount)
            XCTAssertEqual(result.outcomes.last?.service, service)
            XCTAssertNotNil(result.outcomes.last?.failure)
            XCTAssertTrue(result.failure?.contains("not empty after reset") == true)
        }
    }

    func testOnlyResettingTheThreeLegacyServicesIsNotComplete() {
        let incomplete = ResetAllPermissions.Result(outcomes: [
            .init(service: .accessibility, failure: nil),
            .init(service: .postEvent, failure: nil),
            .init(service: .listenEvent, failure: nil)
        ], failure: nil)

        XCTAssertFalse(incomplete.succeeded)
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
        for service in [GlobalResetService.screenCapture, .audioCapture] {
            runner.respond(to: [SystemTool.tccutil, "list", "-s", service.rawValue],
                           with: CommandResult(output: "", exitCode: 0))
        }
        for service in GlobalRepairPlan().services {
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
    enum Failure: LocalizedError {
        case inventory
        var errorDescription: String? { "The running-process list could not be read." }
    }

    var running: [AffectedProcess]
    var error: Failure?
    var failsAfterFirstReset = false
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
        if let error { throw error }
        if failsAfterFirstReset, runner.ranReset { throw Failure.inventory }
        if !snapshots.isEmpty { return snapshots.removeFirst() }
        return running
    }

    func requestTermination(of processes: [AffectedProcess]) {
        resetHadStartedWhenTerminationWasRequested = runner.ranReset
        terminationRequests.append(processes)
        if !refusesTermination { running.removeAll() }
    }
}
