import DoctorCore
import XCTest
@testable import DeviceControlDoctorModule

@MainActor
final class ResetAllSessionTests: XCTestCase {
    func testFailedQuitShowsCurrentStatesAndAllowsRetryAfterExplicitForceQuit() async throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        let app = process(101, name: "App")
        let helper = process(102, name: "browser_crashpad_handler")
        let lifecycle = SessionLifecycle(running: [app, helper])
        lifecycle.survivors = [helper]
        let runner = configuredRunner()
        let session = makeSession(mac: mac, runner: runner, lifecycle: lifecycle)
        XCTAssertFalse(session.canReset)
        XCTAssertFalse(session.allowsRunningApps)
        await session.refresh()

        await session.reset()

        XCTAssertNotNil(session.failure)
        XCTAssertEqual(session.rows.first { $0.process.id == app.id }?.state, .exited)
        let helperRow = try XCTUnwrap(session.rows.first { $0.process.id == helper.id })
        XCTAssertEqual(helperRow.state, .stillRunning)
        XCTAssertTrue(session.canReset, "a stopped attempt must not permanently disable the button")
        XCTAssertFalse(runner.ranReset)
        XCTAssertTrue(lifecycle.forced.isEmpty, "a normal reset must never escalate to Force Quit")

        await session.forceQuit(helperRow.id)
        XCTAssertEqual(lifecycle.forced, [helper])
        XCTAssertEqual(session.rows.first { $0.id == helperRow.id }?.state, .forceQuitRequested,
                       "a successful request is not proof of exit")
        await session.refresh()
        XCTAssertEqual(session.rows.first { $0.id == helperRow.id }?.state, .exited)
        XCTAssertEqual(session.rows.count, 2, "exited rows remain visible")
        await session.reset()
        XCTAssertTrue(session.completed)
        XCTAssertTrue(runner.ranReset)
    }

    func testOverrideIsSessionOnlyAndDoesNotClaimAppsWereClosed() async throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        let runner = configuredRunner()
        let lifecycle = SessionLifecycle(running: [process(103, name: "Teams helper")])
        lifecycle.survivors = lifecycle.running
        let doctor = makeStore(mac: mac, runner: runner, lifecycle: lifecycle)
        let session = ResetAllSession(doctor: doctor)
        await session.refresh()
        session.allowsRunningApps = true

        await session.reset()

        XCTAssertTrue(session.completed)
        XCTAssertEqual(session.runningCount, 1)
        XCTAssertTrue(lifecycle.quitRequests.isEmpty)
        XCTAssertTrue(lifecycle.forced.isEmpty)
        XCTAssertTrue(doctor.events.first?.message.contains("acknowledged the risk") == true)
        XCTAssertFalse(doctor.events.first?.message.contains("required to be closed") == true)
        XCTAssertFalse(ResetAllSession(doctor: doctor).allowsRunningApps,
                       "closing the sheet must discard the acknowledgement")
    }

    func testInventoryFailureMarksRowsUnverifiedAndBlocksEvenAnAcknowledgedOverride() async throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        let runner = configuredRunner()
        let lifecycle = SessionLifecycle(running: [process(104, name: "App")])
        let session = makeSession(mac: mac, runner: runner, lifecycle: lifecycle)
        await session.refresh()
        let id = try XCTUnwrap(session.rows.first?.id)
        lifecycle.inventoryFails = true
        session.allowsRunningApps = true

        await session.refresh()
        await session.reset()
        await session.forceQuit(id)

        XCTAssertNotNil(session.inventoryFailure)
        XCTAssertEqual(session.rows.first?.state, .unverified)
        XCTAssertEqual(session.unverifiedCount, 1)
        XCTAssertTrue(session.activity.contains("unavailable"))
        XCTAssertFalse(session.canReset)
        XCTAssertFalse(runner.ranReset)
        XCTAssertTrue(lifecycle.forced.isEmpty)
        lifecycle.inventoryFails = false
        await session.refresh()
        XCTAssertEqual(session.rows.first?.state, .running)
        XCTAssertTrue(session.canReset)
    }

    func testSameNamedProcessesAndPIDReuseAreDistinctRows() async throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        let runner = configuredRunner()
        let original = process(105, name: "browser_crashpad_handler")
        let second = process(106, name: original.name)
        let lifecycle = SessionLifecycle(running: [original, second])
        let session = makeSession(mac: mac, runner: runner, lifecycle: lifecycle)
        await session.refresh()
        let oldID = try XCTUnwrap(session.rows.first { $0.process.id == original.id }?.id)
        let replacement = process(105, name: original.name, start: 200)
        lifecycle.running = [replacement, second]

        await session.refresh()
        await session.forceQuit(oldID)

        XCTAssertEqual(session.rows.count, 3)
        XCTAssertEqual(session.rows.first { $0.id == oldID }?.state, .exited)
        XCTAssertEqual(session.runningCount, 2)
        XCTAssertTrue(lifecycle.forced.isEmpty, "a stale row must never force quit a replacement PID")
    }

    func testRejectedForceQuitShowsErrorWithoutClaimingExit() async throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        let runner = configuredRunner()
        let lifecycle = SessionLifecycle(running: [process(107, name: "Helper")])
        lifecycle.forceFails = true
        let session = makeSession(mac: mac, runner: runner, lifecycle: lifecycle)
        await session.refresh()
        let id = try XCTUnwrap(session.rows.first?.id)

        await session.forceQuit(id)

        XCTAssertEqual(session.rows.first?.state, .running)
        XCTAssertNotNil(session.rows.first?.detail)
        XCTAssertNotNil(session.failure)
        XCTAssertFalse(runner.ranReset)
    }

    func testClosingTheSheetDuringAnInspectionDoesNotLeaveAFailureNotice() async throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        let runner = configuredRunner()
        runner.withholdListing()
        runner.cancelCallingTask()
        let doctor = makeStore(mac: mac, runner: runner, lifecycle: SessionLifecycle(running: []))
        let session = ResetAllSession(doctor: doctor)

        await Task { await session.refresh() }.value

        XCTAssertNil(doctor.notice)
        XCTAssertNil(session.inventoryFailure)
        XCTAssertNil(session.failure)
        XCTAssertFalse(session.isRefreshing)
        XCTAssertFalse(runner.ranReset)
    }

    private func makeSession(mac: FixtureMac, runner: FakeProcessRunner,
                             lifecycle: SessionLifecycle) -> ResetAllSession {
        ResetAllSession(doctor: makeStore(mac: mac, runner: runner, lifecycle: lifecycle))
    }

    private func makeStore(mac: FixtureMac, runner: FakeProcessRunner,
                           lifecycle: SessionLifecycle) -> DoctorStore {
        DoctorStore(defaults: UserDefaults(suiteName: "ResetAllSessionTests.\(UUID().uuidString)")!,
                    runner: runner, storageURL: mac.watchList, lifecycle: lifecycle,
                    resetTiming: .init(pollNanoseconds: 0, stableSamples: 1, maximumPolls: 3))
    }

    private func configuredRunner() -> FakeProcessRunner {
        let runner = FakeProcessRunner()
        runner.offerListing()
        runner.clearListedServiceAfterReset()
        for service in PermissionService.allCases {
            runner.respond(to: [SystemTool.tccutil, "list", "-s", service.rawValue],
                           with: CommandResult(output: "com.example.App", exitCode: 0))
            runner.respond(to: [SystemTool.tccutil, "reset", service.rawValue],
                           with: CommandResult(output: "", exitCode: 0))
        }
        return runner
    }

    private func process(_ pid: Int32, name: String, start: Int64 = 100) -> AffectedProcess {
        AffectedProcess(processIdentifier: pid, name: name, executablePath: "/fixture/\(name)",
                        canRequestTermination: true,
                        startTime: ProcessStartTime(seconds: start, microseconds: 0),
                        canForceTerminate: true)
    }
}

@MainActor
private final class SessionLifecycle: ApplicationLifecycleManaging {
    var running: [AffectedProcess]
    var survivors: [AffectedProcess] = []
    var inventoryFails = false
    var forceFails = false
    var quitRequests: [[AffectedProcess]] = []
    var forced: [AffectedProcess] = []

    init(running: [AffectedProcess]) { self.running = running }

    func runningProcesses(matching clients: Set<String>) async throws -> [AffectedProcess] {
        if inventoryFails { throw ProcessTerminationError.unreadableIdentity }
        return running
    }

    func requestTermination(of processes: [AffectedProcess]) {
        quitRequests.append(processes)
        running = survivors
    }

    func forceTerminate(_ process: AffectedProcess) throws {
        if forceFails { throw ProcessTerminationError.signalFailed(1) }
        forced.append(process)
        running.removeAll { $0 == process }
        survivors.removeAll { $0 == process }
    }
}
