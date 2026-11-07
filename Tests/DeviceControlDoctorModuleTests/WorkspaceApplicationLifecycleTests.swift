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

    func testDeniedResponsibilityLookupForOwnProcessFailsClosed() {
        for code in [EPERM, EACCES] {
            XCTAssertThrowsError(try SystemProcessInventory.interpretResponsibilityResult(
                responsible: -1, errorNumber: code, processIdentifier: 98_770,
                processUserIdentifier: 501, callerUserIdentifier: 501,
                parentProcessIdentifier: 1
            ))
        }
    }

    func testOtherUsersDeniedResponsibilityLookupFallsBackToParentChain() throws {
        let responsibility = try SystemProcessInventory.interpretResponsibilityResult(
            responsible: -1, errorNumber: EPERM, processIdentifier: 98_772,
            processUserIdentifier: 0, callerUserIdentifier: 501,
            parentProcessIdentifier: 98_773
        )

        XCTAssertEqual(responsibility, .unreadable(parentProcessIdentifier: 98_773),
                       "macOS denies this lookup for every system daemon; that must not block Reset All")
    }

    func testOtherUsersUnexpectedResponsibilityFailureFailsClosed() {
        for code in [EACCES, EINVAL] {
            XCTAssertThrowsError(try SystemProcessInventory.interpretResponsibilityResult(
                responsible: -1, errorNumber: code, processIdentifier: 98_774,
                processUserIdentifier: 0, callerUserIdentifier: 501,
                parentProcessIdentifier: 1
            ))
        }
    }

    func testExitedProcessDuringResponsibilityLookupIsSkipped() throws {
        XCTAssertNil(try SystemProcessInventory.interpretResponsibilityResult(
            responsible: -1, errorNumber: ESRCH, processIdentifier: 98_771,
            processUserIdentifier: 0, callerUserIdentifier: 501,
            parentProcessIdentifier: 1
        ))
    }

    func testKernelIdentityIsReadFromTheCodeSigningBlob() {
        let identifier = Array("com.apple.dt.instruments.dtarbiter.xpc".utf8)
        let length = 8 + identifier.count + 1
        let blob: [UInt8] = [0xFA, 0xDE, 0x71, 0x71,
                             0, 0, UInt8(length >> 8), UInt8(length & 0xFF)]
            + identifier + [0] + [UInt8](repeating: 0xEE, count: 16)

        XCTAssertEqual(SystemProcessInventory.interpretKernelIdentity(status: 0, blob: blob),
                       "com.apple.dt.instruments.dtarbiter.xpc")
    }

    func testMalformedKernelIdentityLeavesTheIdentityUnavailable() {
        let header: [UInt8] = [0xFA, 0xDE, 0x71, 0x71]
        let cases: [(status: Int32, blob: [UInt8])] = [
            (-1, header + [0, 0, 0, 12] + Array("abc".utf8) + [0]),          // csops failed
            (0, header + [0, 0, 0, 64] + Array("abc".utf8) + [0]),           // truncated
            (0, header + [0, 0, 0, 9] + [0]),                                 // empty identifier
            (0, header + [0, 0, 0, 4]),                                       // length below header
            (0, header + [0, 0, 0, 11] + [0xC3, 0x28] + [0]),                 // invalid UTF-8
        ]
        for (status, blob) in cases {
            XCTAssertNil(SystemProcessInventory.interpretKernelIdentity(status: status, blob: blob))
        }
    }

    func testUnreadableSystemDaemonStartedByLaunchdIsNotAffected() async throws {
        let launchd = ProcessIdentity(processIdentifier: 1,
                                      executablePath: "/sbin/launchd",
                                      signingIdentifier: "com.apple.xpc.launchd",
                                      responsibility: .unreadable(parentProcessIdentifier: 0),
                                      userIdentifier: 0)
        let daemon = ProcessIdentity(processIdentifier: 720,
                                     executablePath: "/usr/libexec/tccd",
                                     signingIdentifier: "com.apple.tccd",
                                     responsibility: .unreadable(parentProcessIdentifier: 1),
                                     userIdentifier: 0)
        let lifecycle = WorkspaceApplicationLifecycle(inventory: InventoryFixture(processes: [launchd, daemon]))

        let running = try await lifecycle.runningProcesses(matching: ["com.example.Main"])

        XCTAssertTrue(running.isEmpty)
    }

    func testUnreadableProcessMatchingAClientIsAffected() async throws {
        let daemon = ProcessIdentity(processIdentifier: 721,
                                     executablePath: "/Library/PrivilegedHelperTools/com.example.Main.Daemon",
                                     signingIdentifier: "com.example.Main",
                                     responsibility: .unreadable(parentProcessIdentifier: 1),
                                     userIdentifier: 0)
        let lifecycle = WorkspaceApplicationLifecycle(inventory: InventoryFixture(processes: [daemon]))

        let running = try await lifecycle.runningProcesses(matching: ["com.example.Main"])

        XCTAssertEqual(running.map(\.processIdentifier), [721])
        XCTAssertFalse(running[0].canRequestTermination,
                       "another user's process must stay visible so Reset All waits for it")
    }

    func testUnreadableChildOfAffectedAppStaysAffectedAfterTheAppExits() async throws {
        let app = ProcessIdentity(processIdentifier: 722,
                                  executablePath: "/Applications/Main.app/Contents/MacOS/Main",
                                  signingIdentifier: "com.example.Main")
        let rootHelper = ProcessIdentity(processIdentifier: 723,
                                         executablePath: "/usr/local/libexec/main-root-helper",
                                         signingIdentifier: "com.example.RootHelper",
                                         responsibility: .unreadable(parentProcessIdentifier: 722),
                                         userIdentifier: 0)
        let reparented = ProcessIdentity(processIdentifier: 723,
                                         executablePath: rootHelper.executablePath,
                                         signingIdentifier: "com.example.RootHelper",
                                         responsibility: .unreadable(parentProcessIdentifier: 1),
                                         userIdentifier: 0)
        let inventory = SequencedInventory(snapshots: [[app, rootHelper], [reparented]])
        let lifecycle = WorkspaceApplicationLifecycle(inventory: inventory)

        let beforeQuit = try await lifecycle.runningProcesses(matching: ["com.example.Main"])
        let afterQuit = try await lifecycle.runningProcesses(matching: ["com.example.Main"])

        XCTAssertEqual(Set(beforeQuit.map(\.processIdentifier)), [722, 723])
        XCTAssertEqual(Set(afterQuit.map(\.processIdentifier)), [723],
                       "a privileged child inherits the app's responsibility, even once reparented")
    }

    func testUnreadableProcessFollowsItsParentsKnownResponsibility() async throws {
        let terminal = ProcessIdentity(processIdentifier: 724,
                                       executablePath: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal",
                                       signingIdentifier: "com.apple.Terminal")
        let shell = ProcessIdentity(processIdentifier: 725,
                                    executablePath: "/bin/zsh",
                                    signingIdentifier: "com.apple.zsh",
                                    responsibility: .process(724))
        let sudo = ProcessIdentity(processIdentifier: 726,
                                   executablePath: "/usr/bin/sudo",
                                   signingIdentifier: "com.apple.sudo",
                                   responsibility: .unreadable(parentProcessIdentifier: 725),
                                   userIdentifier: 0)
        let lifecycle = WorkspaceApplicationLifecycle(inventory: InventoryFixture(processes: [terminal, shell, sudo]))

        let running = try await lifecycle.runningProcesses(matching: ["com.apple.Terminal"])

        XCTAssertEqual(Set(running.map(\.processIdentifier)), [724, 725, 726])
    }

    func testUnreadableProcessWhoseParentExitedMidSnapshotDoesNotBlock() async throws {
        let orphan = ProcessIdentity(processIdentifier: 727,
                                     executablePath: "/usr/local/libexec/orphan",
                                     signingIdentifier: "com.example.Orphan",
                                     responsibility: .unreadable(parentProcessIdentifier: 728),
                                     userIdentifier: 0)
        let lifecycle = WorkspaceApplicationLifecycle(inventory: InventoryFixture(processes: [orphan]))

        let running = try await lifecycle.runningProcesses(matching: ["com.example.Main"])

        XCTAssertTrue(running.isEmpty,
                      "macOS reparents the orphan to launchd; the next snapshot would end its chain there too")
    }

    func testUnreadableProcessWhoseParentExitedStillMatchesByItsOwnIdentity() async throws {
        let orphan = ProcessIdentity(processIdentifier: 731,
                                     executablePath: "/usr/local/libexec/main-helper",
                                     signingIdentifier: "com.example.Main",
                                     responsibility: .unreadable(parentProcessIdentifier: 732),
                                     userIdentifier: 0)
        let lifecycle = WorkspaceApplicationLifecycle(inventory: InventoryFixture(processes: [orphan]))

        let running = try await lifecycle.runningProcesses(matching: ["com.example.Main"])

        XCTAssertEqual(running.map(\.processIdentifier), [731])
    }

    func testCyclicParentChainFailsClosed() async {
        let first = ProcessIdentity(processIdentifier: 729,
                                    executablePath: "/tmp/first",
                                    signingIdentifier: "com.example.First",
                                    responsibility: .unreadable(parentProcessIdentifier: 730),
                                    userIdentifier: 0)
        let second = ProcessIdentity(processIdentifier: 730,
                                     executablePath: "/tmp/second",
                                     signingIdentifier: "com.example.Second",
                                     responsibility: .unreadable(parentProcessIdentifier: 729),
                                     userIdentifier: 0)
        let lifecycle = WorkspaceApplicationLifecycle(inventory: InventoryFixture(processes: [first, second]))

        do {
            _ = try await lifecycle.runningProcesses(matching: ["com.example.Main"])
            XCTFail("a cyclic parent chain must not prove that no affected helper is running")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("cycle"))
        }
    }

    func testResponsibleHelperRemainsAffectedAfterItsMainAppExits() async throws {
        let main = ProcessIdentity(processIdentifier: 701,
                                   executablePath: "/Applications/Main.app/Contents/MacOS/Main",
                                   signingIdentifier: "com.example.Main")
        let helper = ProcessIdentity(processIdentifier: 702,
                                     executablePath: "/Library/Application Support/Main/Helper",
                                     signingIdentifier: "com.example.Main.Helper",
                                     responsibility: .process(701))
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
                                     responsibility: .process(705),
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
                                     responsibility: .process(707))
        let owner = ProcessIdentity(processIdentifier: 707,
                                    executablePath: "/tmp/intermediate-owner",
                                    signingIdentifier: "com.example.Main.Owner",
                                    responsibility: .process(708))
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
                                     responsibility: .process(710))
        let owner = ProcessIdentity(processIdentifier: 710,
                                    executablePath: "/tmp/cyclic-owner",
                                    signingIdentifier: "com.example.Main.Owner",
                                    responsibility: .process(709))
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
                                     responsibility: .process(712),
                                     userIdentifier: getuid() + 1)
        let owner = ProcessIdentity(processIdentifier: 712,
                                    executablePath: "/tmp/foreign-owner",
                                    signingIdentifier: "com.example.Main.Owner",
                                    responsibility: .process(713),
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

    /// Reset All passes bundle identifiers, so every live process, including
    /// other users' system daemons, must be attributable without privilege.
    func testLiveLifecycleCanProveAnAbsentBundleClientHasNoRunningProcesses() async throws {
        let lifecycle = WorkspaceApplicationLifecycle(
            inventory: InventoryFixture(processes: try await liveSnapshot())
        )
        let running = try await lifecycle.runningProcesses(
            matching: ["com.example.definitely-not-running"]
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
            default:
                // macOS always denies responsibility lookups for other users'
                // processes to an unprivileged caller. That is the normal
                // case, not a restricted host, so it must not be skipped.
                throw error
            }
            // Some hosts restrict executable paths. Production must refuse
            // the reset there; these success-path checks require a complete,
            // readable inventory.
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
