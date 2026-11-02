import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [ZenProfile] = []
    @Published var profileID: String? = nil
    @Published var records: [BackupRecord] = []
    @Published var selectedID: String?
    @Published var busy = false
    @Published var progress = ""
    @Published var error: String?
    @Published var notice: String?
    @Published var lastSafety: SafetyArchive?
    @Published var showLegacy = false
    @Published var showSafety = false
    private var scanTask: Task<Void, Never>?
    private var generation = UUID()
    let safetyRoot = SafetyArchive.defaultRoot

    var profile: ZenProfile? { profiles.first { $0.id == profileID } }
    var selected: BackupRecord? { records.first { $0.id == selectedID } }
    var current: BackupRecord? {
        records.first { $0.kind == .current && $0.preview?.format == .zen } ?? records.first { $0.kind == .current && $0.preview != nil }
    }
    var visibleRecords: [BackupRecord] {
        records.filter { (showLegacy || $0.kind != .legacy) && (showSafety || $0.kind != .safety) }
    }

    func start() {
        guard NSClassFromString("XCTestCase") == nil else { return }
        do {
            profiles = try ProfileDiscovery.discover()
            profileID = profiles.first?.id
            if profiles.isEmpty { notice = "No Zen profiles found. Choose a profile folder to get started." }
        } catch { self.error = error.localizedDescription }
    }

    func chooseProfile() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Zen profile folder"
        panel.message = "Choose the folder containing prefs.js and your session backups."
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SessionFiles.validateProfile(url)
            let profile = ZenProfile(name: url.lastPathComponent, directory: url, isDefault: false)
            if !profiles.contains(where: { $0.id == profile.id }) { profiles.append(profile) }
            profileID = profile.id
        } catch { self.error = error.localizedDescription }
    }

    func refresh() {
        scanTask?.cancel()
        generation = UUID()
        let token = generation
        guard let profile else { records = []; return }
        let previousSelection = selectedID
        records = []; selectedID = nil; lastSafety = nil
        busy = true; progress = "Reading session backups…"
        let root = safetyRoot
        scanTask = Task {
            let worker = Task.detached(priority: .userInitiated) {
                try BackupCatalog.scan(profile: profile, safetyRoot: root) { done, total in
                    Task { @MainActor [weak self] in
                        guard self?.generation == token else { return }
                        self?.progress = "Reading backup \(done) of \(total)…"
                    }
                }
            }
            do {
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard generation == token, !Task.isCancelled else { return }
                records = result
                lastSafety = try SafetyArchive.list(root: root, profile: profile).first
                selectedID = visibleRecords.first { $0.id == previousSelection }?.id ?? visibleRecords.first { $0.canRestore }?.id ?? visibleRecords.first?.id
            } catch is CancellationError { }
            catch { if generation == token { self.error = error.localizedDescription } }
            if generation == token { busy = false }
        }
    }

    func restoreSelected() {
        guard let selected, let profile, !busy else { return }
        perform(profile: profile) { service in try service.restore(selected, to: profile) }
    }

    func undoLastRestore() {
        guard let lastSafety, let profile, !busy else { return }
        perform(profile: profile, isUndo: true) { service in try service.undo(lastSafety, profile: profile) }
    }

    private func perform(profile: ZenProfile, isUndo: Bool = false, operation: @escaping (RestoreService) throws -> SafetyArchive) {
        busy = true; progress = "Saving a safety copy and verifying the restore…"; notice = nil
        let root = safetyRoot
        Task {
            do {
                let archive = try await Task.detached(priority: .userInitiated) {
                    try operation(RestoreService(safetyRoot: root, isZenRunning: { ZenRuntime.isRunning }))
                }.value
                lastSafety = archive
                notice = isUndo ? "Previous state restored. You can now open Zen." : "Backup restored. Open Zen to load your tabs. A safety copy is available for undo."
                busy = false
                refresh()
            } catch { self.error = error.localizedDescription; busy = false }
        }
    }

    func exportSelected() {
        guard let selected else { return }
        let panel = NSSavePanel()
        panel.title = "Export session backup"
        panel.nameFieldStringValue = selected.file.lastPathComponent
        panel.message = "Session backups include browsing history and may contain saved form or session data. Keep this file private."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            guard destination.standardizedFileURL != selected.file.standardizedFileURL,
                  !destination.resolvingSymlinksInPath().path.hasPrefix(safetyRoot.resolvingSymlinksInPath().path + "/"),
                  !profiles.contains(where: { destination.resolvingSymlinksInPath().path.hasPrefix($0.directory.resolvingSymlinksInPath().path + "/") }) else {
                throw BackupError.invalid("Export to a folder outside your Zen profiles.")
            }
            let data = try SessionFiles.read(selected.file)
            guard selected.digest == SessionFiles.digest(data) else { throw BackupError.changed }
            try SessionFiles.write(data, to: destination)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch { self.error = error.localizedDescription }
    }

    func openZen() {
        Task { do { try await ZenRuntime.open() } catch { self.error = error.localizedDescription } }
    }
}
