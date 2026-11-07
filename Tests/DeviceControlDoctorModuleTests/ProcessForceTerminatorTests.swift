import Darwin
import Foundation
import XCTest
@testable import DeviceControlDoctorModule

@MainActor
final class ProcessForceTerminatorTests: XCTestCase {
    private let start = ProcessStartTime(seconds: 100, microseconds: 23)

    func testVerifiedOwnProcessReceivesOneExplicitKillRequest() throws {
        let process = target()
        var signals: [Int32] = []
        let service = SystemProcessForceTerminator(readIdentity: { _ in
            .init(userIdentifier: geteuid(), executablePath: process.executablePath, startTime: self.start)
        }, sendKill: { signals.append($0); return 0 })

        try service.forceTerminate(process)

        XCTAssertEqual(signals, [process.id])
    }

    func testPIDReuseChangedPathAndDifferentOwnerNeverReceiveASignal() {
        let process = target()
        let identities: [SystemProcessForceTerminator.Identity] = [
            .init(userIdentifier: geteuid(), executablePath: process.executablePath,
                  startTime: .init(seconds: 101, microseconds: 23)),
            .init(userIdentifier: geteuid(), executablePath: process.executablePath,
                  startTime: .init(seconds: 100, microseconds: 24)),
            .init(userIdentifier: geteuid(), executablePath: "/fixture/another-executable", startTime: start),
            .init(userIdentifier: geteuid() + 1, executablePath: process.executablePath, startTime: start)
        ]
        for identity in identities {
            var signals = 0
            let service = SystemProcessForceTerminator(readIdentity: { _ in identity },
                                                       sendKill: { _ in signals += 1; return 0 })
            XCTAssertThrowsError(try service.forceTerminate(process))
            XCTAssertEqual(signals, 0)
        }
    }

    func testSelfSystemAndUnverifiedTargetsAreRejectedBeforeReadingOrSignaling() {
        let targets = [
            target(pid: -1), target(pid: 0), target(pid: 1),
            target(pid: ProcessInfo.processInfo.processIdentifier),
            target(canForce: false), target(hasStartTime: false)
        ]
        for process in targets {
            var reads = 0
            var signals = 0
            let service = SystemProcessForceTerminator(readIdentity: { _ in reads += 1; return nil },
                                                       sendKill: { _ in signals += 1; return 0 })
            XCTAssertThrowsError(try service.forceTerminate(process))
            XCTAssertEqual(reads, 0)
            XCTAssertEqual(signals, 0)
        }
    }

    func testAbsentAndUnreadableIdentitiesNeverReceiveASignal() {
        for throwsOnRead in [false, true] {
            var signals = 0
            let service = SystemProcessForceTerminator(readIdentity: { _ in
                if throwsOnRead { throw ProcessTerminationError.unreadableIdentity }
                return nil
            }, sendKill: { _ in signals += 1; return 0 })
            XCTAssertThrowsError(try service.forceTerminate(target()))
            XCTAssertEqual(signals, 0)
        }
    }

    func testRejectedSignalIsReportedAsFailure() {
        let process = target()
        var signals = 0
        let service = SystemProcessForceTerminator(readIdentity: { _ in
            .init(userIdentifier: geteuid(), executablePath: process.executablePath, startTime: self.start)
        }, sendKill: { _ in signals += 1; errno = EPERM; return -1 })

        XCTAssertThrowsError(try service.forceTerminate(process)) { error in
            XCTAssertTrue(error.localizedDescription.contains("rejected"))
        }
        XCTAssertEqual(signals, 1)
    }

    /// The only live signal in these tests targets a child this test created,
    /// never an installed app or a process selected from someone else's PID.
    func testLiveForceQuitConfirmsInventoryStartTimeAgainstTheKernel() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { if child.isRunning { child.terminate() } }
        let lifecycle = WorkspaceApplicationLifecycle()
        let running: [AffectedProcess]
        do {
            running = try await lifecycle.runningProcesses(matching: ["/bin/sleep"])
        } catch LifecycleError.processPathUnavailable(_, let code) where [EACCES, EPERM, ENOENT].contains(code) {
            throw XCTSkip("Host restricts the complete inventory needed to locate the test child.")
        }
        let process = try XCTUnwrap(running.first { $0.id == child.processIdentifier })
        XCTAssertNotNil(process.startTime)
        XCTAssertTrue(process.canForceTerminate)

        try lifecycle.forceTerminate(process)

        let deadline = Date().addingTimeInterval(3)
        while child.isRunning, Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(child.isRunning)
        if !child.isRunning {
            XCTAssertEqual(child.terminationReason, .uncaughtSignal)
            XCTAssertEqual(child.terminationStatus, SIGKILL)
        }
    }

    private func target(pid: Int32 = 98_765, canForce: Bool = true,
                        hasStartTime: Bool = true) -> AffectedProcess {
        AffectedProcess(processIdentifier: pid, name: "Fixture helper", executablePath: "/fixture/helper",
                        canRequestTermination: false, startTime: hasStartTime ? start : nil,
                        canForceTerminate: canForce)
    }
}
