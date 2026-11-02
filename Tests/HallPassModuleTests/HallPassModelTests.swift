import Foundation
import Testing
import HallPassCore
@testable import HallPassModule

/// The apply flow against a fake service: the automatic backup, the
/// restart flag in the module's defaults, and how each service failure
/// leaves the draft. The generated script's re-check and rollback are
/// covered by HallPassCoreTests' PreferencePlanTests.
@MainActor
struct HallPassModelTests {
    private let baseline = NetworkConfiguration(wifi: ["169.254.0.0/16"], ethernet: nil)

    @Test func applyWritesBackupAndRemembersRestart() async throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        let service = try FakePreferences(baseline: baseline)
        let model = sandbox.model(service)

        await model.load()
        try model.add("10.0.0.1/8", interfaces: NetworkInterface.allCases)
        await model.save()

        #expect(model.error == nil)
        #expect(model.snapshot?.configuration == NetworkConfiguration(wifi: ["169.254.0.0/16", "10.0.0.0/8"],
                                                                     ethernet: ["10.0.0.0/8"]))
        #expect(!model.isDirty)
        #expect(model.needsRestart)

        let files = try sandbox.backupFiles()
        #expect(files.count == 1)
        let backup = try #require(files.first)
        #expect(backup.lastPathComponent.hasPrefix("HallPass-"))
        let permissions = try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        #expect(try ConfigurationBackup.decode(Data(contentsOf: backup)).configuration == baseline)

        // A pane rebuilt later, or after relaunch, reads the flag back.
        let reopened = sandbox.model(service)
        reopened.restoreRestartState()
        #expect(reopened.needsRestart)
        #expect(sandbox.defaults.double(forKey: HallPassModel.restartUptimeKey) > 0)
    }

    @Test func conflictKeepsDraftAndSnapshot() async throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        let model = sandbox.model(try FakePreferences(baseline: baseline, saveFailure: .conflict))

        await model.load()
        try model.add("192.168.1.0/24", interfaces: [.wifi])
        await model.save()

        #expect(model.error == PreferencesServiceError.conflict.errorDescription)
        #expect(model.snapshot?.configuration == baseline)
        #expect(model.isDirty, "the draft survives so the user can reload and redo it")
        #expect(!model.needsRestart)
        #expect(sandbox.defaults.double(forKey: HallPassModel.restartUptimeKey) == 0)
        #expect(try sandbox.backupFiles().count == 1, "the backup is taken before the write")
    }

    @Test func cancelledAuthorizationChangesNothing() async throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        let model = sandbox.model(try FakePreferences(baseline: baseline, saveFailure: .cancelled))

        await model.load()
        try model.add("192.168.1.0/24", interfaces: [.wifi])
        await model.save()

        #expect(model.error == "The administrator dialog was cancelled.")
        #expect(model.snapshot?.configuration == baseline)
        #expect(model.isDirty)
        #expect(!model.needsRestart)
    }

    @Test(arguments: [PreferencesServiceError.rollbackFailed, .verificationFailed])
    func unknownSystemStateForcesReloadAndRestart(_ failure: PreferencesServiceError) async throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        let model = sandbox.model(try FakePreferences(baseline: baseline, saveFailure: failure))

        await model.load()
        try model.add("192.168.1.0/24", interfaces: [.wifi])
        await model.save()

        #expect(model.error == failure.errorDescription)
        #expect(!model.isLoaded, "the system state is unknown, so the pane asks for a reload")
        #expect(model.needsRestart)
        #expect(sandbox.defaults.double(forKey: HallPassModel.restartUptimeKey) > 0)
    }

    @Test func previewNeverTouchesTheSystem() async throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        let service = try FakePreferences(baseline: baseline)
        let model = sandbox.model(service)

        model.startDemo()
        #expect(model.isDemo)
        try model.add("192.168.1.0/24", interfaces: [.wifi])
        await model.save()
        await model.load()

        #expect(await service.loads == 0)
        #expect(await service.saves.isEmpty)
        #expect(try sandbox.backupFiles().isEmpty)
        #expect(!model.needsRestart)
    }

    @Test func restartFlagFromAnotherBootIsIgnored() {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        let defaults = sandbox.defaults
        defaults.set(120.0, forKey: HallPassModel.restartUptimeKey)
        defaults.set(1_000_000.0, forKey: HallPassModel.restartBootTimeKey)

        let model = HallPassModel(defaults: defaults, service: try! FakePreferences(baseline: baseline),
                                  backupLocation: sandbox.backups)
        model.restoreRestartState()
        #expect(!model.needsRestart)
    }

    @Test func backupsStayInTheStandaloneAppsFolder() throws {
        let directory = try HallPassModel.standardBackupDirectory()
        #expect(directory.path.hasSuffix("Library/Application Support/HallPass/Backups"))
    }
}
