import AppKit
import SwiftUI
import MurtenCore
import ZenBackupManagerCore

/// The pane's state. The provider owns it for the app's lifetime, so a scan
/// or a restore survives navigating away from the pane.
@MainActor
final class AppModel: ObservableObject {
    /// How a finished scan picks the backup the detail shows.
    enum Selection {
        /// The previous selection while it exists, else the newest restorable
        /// backup: the standalone app's behavior.
        case previousOrNewestRestorable
        /// The current state only. A suggestion preselects no backup to
        /// restore (docs/modules.md, Zen Backup Manager).
        case currentState
    }

    @Published var profiles: [ZenProfile] = []
    /// Changes go through `selectProfile(_:)`, which re-scans.
    @Published private(set) var profileID: String? = nil
    @Published var records: [BackupRecord] = []
    @Published var selectedID: String?
    @Published var busy = false
    @Published var progress = ""
    @Published var error: String?
    @Published var notice: String?
    @Published var lastSafety: SafetyArchive?
    @Published var showLegacy = false
    @Published var showSafety = false
    /// True while a restore or undo is writing session files; quitting then
    /// needs confirmation.
    private(set) var isWritingSession = false
    private var scanTask: Task<Void, Never>?
    private var generation = UUID()
    private var hasStarted = false
    /// Folders the user chose this session. They stay listed when a
    /// suggestion re-discovers Zen's profiles.
    private var chosenProfiles: [ZenProfile] = []
    let zenRoot: URL
    let safetyRoot: URL

    init(zenRoot: URL, safetyRoot: URL) {
        self.zenRoot = zenRoot
        self.safetyRoot = safetyRoot
    }

    var profile: ZenProfile? { profiles.first { $0.id == profileID } }
    var selected: BackupRecord? { records.first { $0.id == selectedID } }
    var current: BackupRecord? {
        records.first { $0.kind == .current && $0.preview?.format == .zen } ?? records.first { $0.kind == .current && $0.preview != nil }
    }
    var visibleRecords: [BackupRecord] {
        records.filter { (showLegacy || $0.kind != .legacy) && (showSafety || $0.kind != .safety) }
    }

    /// The pane appeared. Until a visit finds profiles, every visit discovers
    /// them and scans, as the standalone app did at launch; the suite runs far
    /// longer than one launch, so a failed or empty discovery is retried.
    /// After that a plain visit keeps its state. A suggestion's route
    /// discovers again, opens the profile it names and re-scans without
    /// selecting a backup to restore. Nothing starts while a restore is
    /// writing: the pane stays on that profile, which re-scans when it ends.
    func appear(for route: ModuleRoute?) {
        let fromSuggestion = route?.action == ZenBackupRoute.timelineAction
        guard !isWritingSession, !hasStarted || fromSuggestion else { return }

        do {
            let discovered = try ProfileDiscovery.discover(root: zenRoot)
            profiles = discovered + chosenProfiles.filter { chosen in !discovered.contains { $0.id == chosen.id } }
        } catch {
            self.error = error.localizedDescription
            return
        }
        guard !profiles.isEmpty else {
            notice = "No Zen profiles found. Choose a profile folder to get started."
            return
        }

        hasStarted = true
        let requested = route?.context[ZenBackupRoute.profileKey]
        profileID = profiles.first { $0.id == requested }?.id ?? profiles.first { $0.id == profileID }?.id ?? profiles.first?.id
        notice = nil
        refresh(selecting: fromSuggestion ? .currentState : .previousOrNewestRestorable)
    }

    /// The profile picker and Choose Folder land here.
    func selectProfile(_ id: String?) {
        guard id != profileID else { return }
        profileID = id
        notice = nil
        refresh()
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
            if !profiles.contains(where: { $0.id == profile.id }) { profiles.append(profile); chosenProfiles.append(profile) }
            selectProfile(profile.id)
        } catch { self.error = error.localizedDescription }
    }

    func refresh(selecting selection: Selection = .previousOrNewestRestorable) {
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
                switch selection {
                case .previousOrNewestRestorable:
                    selectedID = visibleRecords.first { $0.id == previousSelection }?.id ?? visibleRecords.first { $0.canRestore }?.id ?? visibleRecords.first?.id
                case .currentState:
                    selectedID = visibleRecords.first { $0.kind == .current }?.id
                }
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
        busy = true; isWritingSession = true; progress = "Saving a safety copy and verifying the restore…"; notice = nil
        let root = safetyRoot
        Task {
            defer { isWritingSession = false }
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
