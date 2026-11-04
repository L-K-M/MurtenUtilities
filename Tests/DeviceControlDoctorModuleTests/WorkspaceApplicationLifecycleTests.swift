import Darwin
import XCTest
@testable import DeviceControlDoctorModule

@MainActor
final class WorkspaceApplicationLifecycleTests: XCTestCase {
    func testFindsBackgroundProcessBySigningIdentifier() async throws {
        let process = ProcessIdentity(processIdentifier: 98_765,
                                      executablePath: "/Applications/Helper.app/Contents/MacOS/Helper",
                                      signingIdentifier: "com.example.Helper")
        let lifecycle = WorkspaceApplicationLifecycle(inventory: InventoryFixture(processes: [process]))

        let running = try await lifecycle.runningProcesses(matching: ["com.example.Helper"])

        XCTAssertEqual(running, [AffectedProcess(processIdentifier: 98_765,
                                                 name: "Helper",
                                                 executablePath: process.executablePath,
                                                 canRequestTermination: false)])
    }

    func testFindsCommandLineProcessByExactPath() async throws {
        let path = "/Applications/Tool With Spaces.app/Contents/MacOS/Tool With Spaces"
        let process = ProcessIdentity(processIdentifier: 98_766,
                                      executablePath: path,
                                      signingIdentifier: nil)
        let lifecycle = WorkspaceApplicationLifecycle(inventory: InventoryFixture(processes: [process]))

        let running = try await lifecycle.runningProcesses(matching: [path])

        XCTAssertEqual(running.map(\.processIdentifier), [98_766])
        XCTAssertFalse(running[0].canRequestTermination,
                       "a non-Workspace process must remain visible so Reset All fails closed")
    }

    func testDoesNotAllowTheCurrentProcessToBeTerminated() async throws {
        let processIdentifier = ProcessInfo.processInfo.processIdentifier
        let process = ProcessIdentity(processIdentifier: processIdentifier,
                                      executablePath: Bundle.main.executableURL?.path ?? "/usr/bin/xctest",
                                      signingIdentifier: "com.example.Current")
        let lifecycle = WorkspaceApplicationLifecycle(inventory: InventoryFixture(processes: [process]))

        let running = try await lifecycle.runningProcesses(matching: ["com.example.Current"])

        XCTAssertEqual(running.count, 1)
        XCTAssertFalse(running[0].canRequestTermination)
    }

    func testInventoryFailurePropagatesInsteadOfAssumingNothingIsRunning() async {
        let lifecycle = WorkspaceApplicationLifecycle(inventory: InventoryFixture(error: InventoryFixture.Error.failed))

        do {
            _ = try await lifecycle.runningProcesses(matching: ["com.example.App"])
            XCTFail("inventory failure must fail closed")
        } catch {
            XCTAssertEqual(error as? InventoryFixture.Error, .failed)
        }
    }

    func testDisappearingProcessDuringOwnerLookupIsSkipped() throws {
        let userIdentifier = try SystemProcessInventory.interpretUserIdentifierQuery(
            status: 0,
            returnedSize: 0,
            expectedSize: 512,
            userIdentifier: getuid(),
            errorNumber: 0,
            processIdentifier: 98_767
        )

        XCTAssertNil(userIdentifier)
    }

    func testMissingExecutablePathIsSkippedWhenProcessIsConfirmedAbsent() {
        XCTAssertNoThrow(try SystemProcessInventory.validateExecutablePathFailure(
            errorNumber: ENOENT,
            processIdentifier: 98_768,
            processConfirmedAbsent: true
        ))
    }

    func testMissingExecutablePathFailsClosedWhileProcessMayStillExist() {
        XCTAssertThrowsError(try SystemProcessInventory.validateExecutablePathFailure(
            errorNumber: ENOENT,
            processIdentifier: 98_769,
            processConfirmedAbsent: false
        ))
    }

    func testDeniedResponsibilityLookupFailsClosed() {
        for code in [EPERM, EACCES] {
            XCTAssertThrowsError(try SystemProcessInventory.interpretResponsibilityResult(
                responsible: -1, errorNumber: code, processIdentifier: 98_770
            ))
        }
    }

    func testExitedProcessDuringResponsibilityLookupIsSkipped() throws {
        XCTAssertNil(try SystemProcessInventory.interpretResponsibilityResult(
            responsible: -1, errorNumber: ESRCH, processIdentifier: 98_771
        ))
    }

    func testResponsibleHelperRemainsAffectedAfterItsMainAppExits() async throws {
        let main = ProcessIdentity(processIdentifier: 701,
                                   executablePath: "/Applications/Main.app/Contents/MacOS/Main",
                                   signingIdentifier: "com.example.Main")
        let helper = ProcessIdentity(processIdentifier: 702,
                                     executablePath: "/Library/Application Support/Main/Helper",
                                     signingIdentifier: "com.example.Main.Helper",
                                     responsibleProcessIdentifier: 701)
        let inventory = SequencedInventory(snapshots: [[main, helper], [helper]])
        let lifecycle = WorkspaceApplicationLifecycle(inventory: inventory)

        let beforeQuit = try await lifecycle.runningProcesses(matching: ["com.example.Main"])
        let afterQuit = try await lifecycle.runningProcesses(matching: ["com.example.Main"])

        XCTAssertEqual(Set(beforeQuit.map(\.processIdentifier)), [701, 702])
        XCTAssertEqual(afterQuit.map(\.processIdentifier), [702],
                       "a helper already attributed to the app must not disappear from later checks")
    }

    func testUnknownSigningIdentityFailsClosed() async {
        let unknown = ProcessIdentity(processIdentifier: 703,
                                      executablePath: "/tmp/unknown-process",
                                      signingIdentifier: nil,
                                      enclosingAppIdentifier: "com.example.Unrelated",
                                      signingIdentityAvailable: false)
        let lifecycle = WorkspaceApplicationLifecycle(inventory: InventoryFixture(processes: [unknown]))

        do {
            _ = try await lifecycle.runningProcesses(matching: ["com.example.Main"])
            XCTFail("an uninspectable background process must not be assumed unrelated")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("signing identity"))
        }
    }

    func testMissingResponsibleAppInAnotherSessionFailsClosed() async {
        let helper = ProcessIdentity(processIdentifier: 704,
                                     executablePath: "/tmp/other-session-helper",
                                     signingIdentifier: "com.example.Main.Helper",
                                     responsibleProcessIdentifier: 705,
                                     userIdentifier: getuid() + 1)
        let lifecycle = WorkspaceApplicationLifecycle(inventory: InventoryFixture(processes: [helper]))

        do {
            _ = try await lifecycle.runningProcesses(matching: ["com.example.Main"])
            XCTFail("an unavailable responsible app must not hide an affected helper in another session")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("responsible app"))
        }
    }

    func testMissingResponsibleAncestorFailsClosed() async {
        let helper = ProcessIdentity(processIdentifier: 706,
                                     executablePath: "/tmp/nested-helper",
                                     signingIdentifier: "com.example.Main.Helper",
                                     responsibleProcessIdentifier: 707)
        let owner = ProcessIdentity(processIdentifier: 707,
                                    executablePath: "/tmp/intermediate-owner",
                                    signingIdentifier: "com.example.Main.Owner",
                                    responsibleProcessIdentifier: 708)
        let lifecycle = WorkspaceApplicationLifecycle(inventory: InventoryFixture(processes: [helper, owner]))

        do {
            _ = try await lifecycle.runningProcesses(matching: ["com.example.Main"])
            XCTFail("an incomplete responsibility chain must not prove that no affected helper is running")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("responsible app"))
        }
    }

    func testCyclicResponsibilityFailsClosed() async {
        let helper = ProcessIdentity(processIdentifier: 709,
                                     executablePath: "/tmp/cyclic-helper",
                                     signingIdentifier: "com.example.Main.Helper",
                                     responsibleProcessIdentifier: 710)
        let owner = ProcessIdentity(processIdentifier: 710,
                                    executablePath: "/tmp/cyclic-owner",
                                    signingIdentifier: "com.example.Main.Owner",
                                    responsibleProcessIdentifier: 709)
        let lifecycle = WorkspaceApplicationLifecycle(inventory: InventoryFixture(processes: [helper, owner]))

        do {
            _ = try await lifecycle.runningProcesses(matching: ["com.example.Main"])
            XCTFail("a cyclic responsibility chain must not prove that no affected helper is running")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("responsib"))
        }
    }

    func testFindsAnAffectedHelpersCompleteChainInAnotherSession() async throws {
        let helper = ProcessIdentity(processIdentifier: 711,
                                     executablePath: "/tmp/foreign-helper",
                                     signingIdentifier: "com.example.Main.Helper",
                                     responsibleProcessIdentifier: 712,
                                     userIdentifier: getuid() + 1)
        let owner = ProcessIdentity(processIdentifier: 712,
                                    executablePath: "/tmp/foreign-owner",
                                    signingIdentifier: "com.example.Main.Owner",
                                    responsibleProcessIdentifier: 713,
                                    userIdentifier: getuid() + 1)
        let app = ProcessIdentity(processIdentifier: 713,
                                  executablePath: "/tmp/foreign-app",
                                  signingIdentifier: "com.example.Main",
                                  userIdentifier: getuid() + 1)
        let lifecycle = WorkspaceApplicationLifecycle(inventory: InventoryFixture(processes: [helper, owner, app]))

        let running = try await lifecycle.runningProcesses(matching: ["com.example.Main"])

        XCTAssertEqual(Set(running.map(\.processIdentifier)), [711, 712, 713])
    }

    func testLiveInventoryContainsTheTestProcess() async throws {
        let processes = try await liveSnapshot()
        XCTAssertTrue(processes.contains { $0.processIdentifier == ProcessInfo.processInfo.processIdentifier })
    }

    func testLiveLifecycleCanProveAnAbsentClientHasNoRunningProcesses() async throws {
        let lifecycle = WorkspaceApplicationLifecycle(
            inventory: InventoryFixture(processes: try await liveSnapshot())
        )
        let running = try await lifecycle.runningProcesses(
            matching: ["/definitely/not/a/live/executable"]
        )
        XCTAssertTrue(running.isEmpty)
    }

    private func liveSnapshot() async throws -> [ProcessIdentity] {
        do {
            return try await SystemProcessInventory().snapshot()
        } catch let error as LifecycleError {
            switch error {
            case .processPathUnavailable(_, let code) where [ENOENT, EACCES, EPERM].contains(code):
                break
            case .responsibilityReadFailed(_, let code) where [EACCES, EPERM].contains(code):
                break
            default:
                throw error
            }
            // Some hosts restrict executable paths or responsibility queries.
            // Production must refuse the reset there; these success-path
            // checks require a complete, readable inventory.
            throw XCTSkip("Host prevents a complete process inventory: \(error.localizedDescription)")
        }
    }
}

private struct InventoryFixture: ProcessInventoryReading {
    enum Error: Swift.Error, Equatable { case failed }

    var processes: [ProcessIdentity] = []
    var error: (any Swift.Error)?

    func snapshot() async throws -> [ProcessIdentity] {
        if let error { throw error }
        return processes
    }
}

private actor SequencedInventory: ProcessInventoryReading {
    private var snapshots: [[ProcessIdentity]]

    init(snapshots: [[ProcessIdentity]]) {
        self.snapshots = snapshots
    }

    func snapshot() async throws -> [ProcessIdentity] {
        return snapshots.isEmpty ? [] : snapshots.removeFirst()
    }
}
