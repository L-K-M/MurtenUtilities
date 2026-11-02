import Foundation
import Testing
import HallPassCore
@testable import HallPassModule

/// The apply flow against a fake service: the automatic backup, the draft
/// recovery file, the restart reminder in the module's defaults, and what
/// each service failure leaves behind. The generated script's re-check and
/// rollback are covered by HallPassCoreTests' PreferencePlanTests.
@MainActor
struct ApplyFlowTests {
    private let baseline = NetworkConfiguration(wifi: ["169.254.0.0/16"], ethernet: nil)

    @Test func applyWritesBackupClearsRecoveryAndRemembersRestart() async throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        let service = try FakePreferences(baseline: baseline)
        let model = sandbox.model(service)

        await model.load()
        try model.add("10.0.0.1/8", interfaces: NetworkInterface.allCases)
        #expect(try BackupStore(root: sandbox.root).loadRecovery()?.draft == model.draft)
        await model.save()

        #expect(model.error == nil)
        #expect(model.snapshot?.configuration == NetworkConfiguration(wifi: ["169.254.0.0/16", "10.0.0.0/8"],
                                                                     ethernet: ["10.0.0.0/8"]))
        #expect(!model.isDirty)
        #expect(model.needsRestart)
        #expect(try BackupStore(root: sandbox.root).loadRecovery() == nil)

        let files = try sandbox.backupFiles()
        #expect(files.count == 1)
        let backup = try #require(files.first)
        #expect(backup.lastPathComponent.hasPrefix("HallPass-"))
        let permissions = try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
        #expect(try ConfigurationBackup.decode(Data(contentsOf: backup)).configuration == baseline)

        // A provider created at the next launch reads the reminder back.
        let reopened = sandbox.model(service)
        reopened.restoreSession()
        #expect(reopened.needsRestart)
    }

    @Test func conflictKeepsTheDraftRecoverable() async throws {
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
        #expect(sandbox.defaults.double(forKey: "restartRequiredAtUptime") == 0)
        #expect(try sandbox.backupFiles().count == 1, "the backup is taken before the write")
        #expect(try BackupStore(root: sandbox.root).loadRecovery()?.draft == model.draft)
    }

    @Test func cancelledAuthorizationKeepsTheDraft() async throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        let model = sandbox.model(try FakePreferences(baseline: baseline, saveFailure: .cancelled))

        await model.load()
        try model.add("192.168.1.0/24", interfaces: [.wifi])
        await model.save()

        #expect(model.error == nil)
        #expect(model.notice == "Applying cancelled. The draft is kept.")
        #expect(model.snapshot?.configuration == baseline)
        #expect(model.isDirty)
        #expect(!model.needsRestart)
    }

    @Test(arguments: [PreferencesServiceError.rollbackFailed, .verificationFailed])
    func unknownSystemStateRequiresReloadAndRestart(_ failure: PreferencesServiceError) async throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        let model = sandbox.model(try FakePreferences(baseline: baseline, saveFailure: failure))

        await model.load()
        try model.add("192.168.1.0/24", interfaces: [.wifi])
        await model.save()

        #expect(model.error == failure.errorDescription)
        #expect(model.requiresReload, "the system state is unknown, so the pane asks for a reload")
        #expect(!model.canEdit)
        #expect(model.needsRestart)
        #expect(sandbox.defaults.double(forKey: "restartRequiredAtUptime") > 0)
    }

    @Test func previewNeverTouchesTheSystem() async throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        let service = try FakePreferences(baseline: baseline)
        let model = sandbox.model(service)

        model.startDemo()
        #expect(model.isDemo)
        try model.add("10.0.0.0/8", interfaces: [.wifi])
        await model.save()
        await model.load()

        #expect(await service.loads == 0)
        #expect(await service.saves.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: sandbox.root.path))
        #expect(!model.needsRestart)
    }

    @Test func restartReminderFromAnotherBootIsIgnored() throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.defaults.set(120.0, forKey: "restartRequiredAtUptime")
        sandbox.defaults.set(1_000_000.0, forKey: "restartRequiredBootTime")

        let model = sandbox.model(try FakePreferences(baseline: baseline))
        model.restoreSession()
        #expect(!model.needsRestart)
    }

    @Test func undoHistoryLeavesWithThePane() throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        let model = sandbox.model(try FakePreferences(baseline: baseline), mode: .preview)
        let window = UndoManager()
        window.groupsByEvent = false
        model.useUndoManager(window)

        try model.add("10.0.0.0/8", interfaces: [.wifi])
        #expect(window.canUndo)

        let draft = model.draft
        model.releaseUndoManager()
        // Undo on the home screen must not reach the draft.
        if window.canUndo { window.undo() }
        let stillShared = model.undoManager === window
        #expect(model.draft == draft)
        #expect(!stillShared)
    }
}
