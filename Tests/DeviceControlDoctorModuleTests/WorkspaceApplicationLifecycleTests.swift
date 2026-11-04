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

    func testLiveInventoryContainsTheTestProcess() async throws {
        let processes = try await SystemProcessInventory().snapshot()
        XCTAssertTrue(processes.contains { $0.processIdentifier == ProcessInfo.processInfo.processIdentifier })
    }

    func testLiveLifecycleCanProveAnAbsentClientHasNoRunningProcesses() async throws {
        let lifecycle = WorkspaceApplicationLifecycle()
        let running = try await lifecycle.runningProcesses(matching: ["com.example.DefinitelyAbsent"])
        XCTAssertTrue(running.isEmpty)
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
