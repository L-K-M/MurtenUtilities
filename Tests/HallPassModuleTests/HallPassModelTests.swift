import AppKit
import Foundation
import HallPassCore
import Testing
@testable import HallPassModule

@MainActor
struct HallPassModelTests {
    @Test func addingToBothInterfacesIsOneNamedUndo() throws {
        let model = preview()
        try model.add("10.1.2.3/8", interfaces: NetworkInterface.allCases)
        #expect(model.draft.wifi?.last == "10.0.0.0/8")
        #expect(model.draft.ethernet?.last == "10.0.0.0/8")
        #expect(model.undoManager.undoActionName == "Add Network Range")

        model.undoManager.undo()
        #expect(model.draft == .example)
        #expect(!model.isDirty)
        model.undoManager.redo()
        #expect(model.draft.wifi?.last == "10.0.0.0/8")
        #expect(model.draft.ethernet?.last == "10.0.0.0/8")
    }

    @Test func editRemovalResetAndDiscardCanBeUndone() throws {
        let model = preview()
        try model.edit(0, notation: "10.0.0.1/32", interface: .wifi)
        let edited = model.draft
        model.remove([0, 1], interface: .wifi)
        #expect(model.draft.wifi == nil)
        #expect(model.undoManager.undoActionName == "Remove Network Ranges")
        model.undoManager.undo()
        #expect(model.draft == edited)

        model.resetDraft()
        #expect(model.draft == .init())
        model.undoManager.undo()
        #expect(model.draft == edited)
        model.discard()
        #expect(model.draft == .example)
        model.undoManager.undo()
        #expect(model.draft == edited)
    }

    @Test func importIsUndoableAndExportUsesSavedState() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BackupStore(root: directory)
        let imported = NetworkConfiguration(wifi: ["legacy", "legacy"], ethernet: [])
        let backup = directory.appendingPathComponent("backup.json")
        try store.export(imported, to: backup)
        let model = preview()
        model.importBackup(from: backup)
        #expect(model.draft == imported)
        model.remove([0], interface: .wifi)
        #expect(model.draft.wifi == ["legacy"])
        model.undoManager.undo()
        #expect(model.draft == imported)
        model.undoManager.undo()
        #expect(model.draft == .example)
        model.undoManager.redo()

        let exported = directory.appendingPathComponent("export.json")
        model.exportBackup(to: exported)
        #expect(try store.readBackup(at: exported) == .example)
    }

    @Test func corruptImportDoesNotAlterTheDraftOrUndoHistory() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("invalid.json")
        try Data("not JSON".utf8).write(to: url)
        let model = preview()
        model.importBackup(from: url)
        #expect(model.draft == .example)
        #expect(!model.undoManager.canUndo)
        #expect(model.error != nil)
    }

    @Test func previewCommitEndsDraftUndoWithoutSystemWrites() async throws {
        let model = preview()
        try model.add("10.0.0.0/8", interfaces: [.wifi])
        await model.save()
        #expect(!model.isDirty)
        #expect(!model.undoManager.canUndo)
        #expect(!model.needsRestart)
        #expect(model.lastBackup == nil)
        #expect(model.snapshot?.configuration == model.draft)
    }

    @Test func recoverySurvivesAnotherModelAndDiscardRemovesIt() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BackupStore(root: directory)
        let baseline = try PreferencesSnapshot(configuration: .example)
        let draft = try NetworkConfiguration.example.adding("10.0.0.0/8", to: [.ethernet])
        try store.saveRecovery(DraftRecovery(baseline: baseline, draft: draft))

        let first = HallPassModel(defaults: defaults(), backups: store)
        first.restoreSession()
        first.undoManager.groupsByEvent = false
        #expect(first.recoveredDraft)
        #expect(first.draft == draft)
        try first.edit(0, notation: "fe80::/10", interface: .wifi)
        let second = HallPassModel(defaults: defaults(), backups: store)
        second.restoreSession()
        #expect(second.draft == first.draft)
        #expect(second.snapshot?.xml == baseline.xml)
        second.discard()
        #expect(try store.loadRecovery() == nil)
        #expect(!second.isDirty)
    }

    @Test func previewNeverCreatesRecoveryOrAutomaticBackups() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = HallPassModel(defaults: defaults(), mode: .preview, backups: BackupStore(root: directory))
        try model.add("10.0.0.0/8", interfaces: [.wifi])
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func automaticBackupsRemainPrivateAndReadable() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BackupStore(root: directory)
        let original = NetworkConfiguration(wifi: [], ethernet: ["old", "old"])
        let url = try store.automaticBackup(original)
        #expect(try store.readBackup(at: url) == original)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func unsupportedRecoverySurvivesLoadingAndLaterEdits() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = Data(#"{"formatVersion":99,"baselineXML":"future format","draft":{}}"#.utf8)
        try original.write(to: directory.appendingPathComponent("Draft.json"))
        let model = HallPassModel(defaults: defaults(), backups: BackupStore(root: directory), service: try LoadedPreferences())
        model.restoreSession()
        #expect(model.error != nil)
        await model.load()
        try model.add("10.0.0.0/8", interfaces: [.wifi])
        #expect(try files(in: directory).contains { (try? Data(contentsOf: $0)) == original })
    }

    @Test func unreadableRecoverySurvivesASuccessfulLoad() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let baseline = try PreferencesSnapshot(configuration: .example)
        let original = try DraftRecovery(baseline: baseline, draft: .init(wifi: ["fe80::/10"])).encoded()
        let url = directory.appendingPathComponent("Draft.json")
        try original.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        let model = HallPassModel(defaults: defaults(), backups: BackupStore(root: directory), service: try LoadedPreferences())
        model.restoreSession()
        #expect(model.error != nil)
        await model.load()

        let retained = try files(in: directory)
        #expect(retained.count == 1)
        for file in retained {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        #expect(retained.contains { (try? Data(contentsOf: $0)) == original })
    }

    @Test func failedPreservationStillProtectsTheOriginalAfterPermissionsReturn() async throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let original = Data(#"{"formatVersion":99,"baselineXML":"future format","draft":{}}"#.utf8)
        try original.write(to: directory.appendingPathComponent("Draft.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        let model = HallPassModel(defaults: defaults(), backups: BackupStore(root: directory), service: try LoadedPreferences())
        model.restoreSession()
        #expect(model.error != nil)

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        await model.load()
        try model.add("10.0.0.0/8", interfaces: [.wifi])
        #expect(try files(in: directory).contains { (try? Data(contentsOf: $0)) == original })
    }

    @Test func endingPreviewRestoresTheUntouchedRealDraft() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BackupStore(root: directory)
        let baseline = try PreferencesSnapshot(configuration: .example)
        let draft = NetworkConfiguration(wifi: ["fe80::/10"], ethernet: [])
        let original = try DraftRecovery(baseline: baseline, draft: draft).encoded()
        let url = directory.appendingPathComponent("Draft.json")
        try original.write(to: url)
        let model = HallPassModel(defaults: defaults(), mode: .preview, backups: store)
        model.restoreSession()
        #expect(model.draft == .example)
        #expect(try Data(contentsOf: url) == original)

        model.leaveDemo()
        #expect(model.recoveredDraft)
        #expect(model.draft == draft)
        #expect(model.snapshot?.xml == baseline.xml)
        #expect(try Data(contentsOf: url) == original)
    }

    private func files(in directory: URL) throws -> [URL] {
        let enumerator = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]))
        return enumerator.allObjects.compactMap { $0 as? URL }.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    private func preview() -> HallPassModel {
        let model = HallPassModel(defaults: defaults(), mode: .preview)
        model.undoManager.groupsByEvent = false
        return model
    }

    /// An empty domain the test never writes to: none of these tests
    /// applies to the system, so the restart reminder is only read.
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "HallPassModelTests.\(UUID().uuidString)")!
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HallPassModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor LoadedPreferences: PreferencesServicing {
    private let snapshot: PreferencesSnapshot

    init() throws {
        snapshot = try PreferencesSnapshot(configuration: .example)
    }

    func load() -> PreferencesSnapshot { snapshot }

    func save(_ plan: PreferencePlan) throws -> PreferencesSnapshot {
        throw PreferencesServiceError.commandFailed("Unexpected test write")
    }
}
