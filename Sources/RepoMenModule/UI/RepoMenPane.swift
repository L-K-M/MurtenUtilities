import SwiftUI
import MurtenCore
import MurtenModuleKit
import RepoMenCore

/// The pane the suite shows for RepoMen: the standalone app's window content,
/// fed the provider's long-lived models, with the standalone Scan and Items
/// menus published to the suite's Tool menu.
struct RepoMenPane: View {
    let route: ModuleRoute?
    @ObservedObject var model: AppModel
    @ObservedObject var snapshotModel: SnapshotModel
    let preferences: Preferences
    let managedStorage: ManagedStorageModel
    let autoTrash: AutoTrashController

    var body: some View {
        ContentView()
            .environmentObject(model)
            .environmentObject(preferences)
            .environmentObject(snapshotModel)
            .environmentObject(managedStorage)
            .environmentObject(autoTrash)
            .frame(minWidth: 780, minHeight: 460)
            // Once per appearance: the suite rebuilds the pane for every route.
            .onAppear { model.handleOpen(route) }
            .moduleCommands(commands)
    }

    /// The standalone app's Scan and Items menus, shortcuts unchanged.
    private var commands: [ModuleCommand] {
        let scanBlocked = model.isBusy || model.isReclaiming || model.isSystemScanning
        let selection = model.tableSelection
        return [
            ModuleCommand("Scan Now", shortcut: KeyboardShortcut("r"), isEnabled: !scanBlocked) {
                model.startScan()
            },
            // Ellipsis: it always costs an admin-password prompt.
            ModuleCommand("Scan System Areas…", shortcut: KeyboardShortcut("r", modifiers: [.command, .shift]),
                          isEnabled: !scanBlocked) {
                model.scanSystemAreas()
            },
            // Selects the sidebar row; listing is read-only and needs no password.
            ModuleCommand("Time Machine Snapshots", shortcut: KeyboardShortcut("s", modifiers: [.command, .shift])) {
                model.sidebarSelection = .snapshots
            },
            ModuleCommand("Stop Scan", shortcut: KeyboardShortcut("."),
                          isEnabled: model.isBusy || model.isSystemScanning) {
                if model.isSystemScanning {
                    model.cancelSystemScan()
                } else {
                    model.cancelScan()
                }
            },
            // ⌘⌫ only opens the confirmation dialog; the destructive step still
            // takes an explicit click there.
            ModuleCommand("Reclaim Checked…", shortcut: KeyboardShortcut(.delete, modifiers: .command),
                          isEnabled: !model.checkedItems.isEmpty && !model.isReclaiming && !model.isSystemScanning
                              && !model.isBusy
                              && model.sidebarSelection != .managedStorage
                              && model.sidebarSelection != .autoTrashLog) {
                model.confirmingReclaim = true
            },
            ModuleCommand("Reveal in Finder", shortcut: KeyboardShortcut(.return, modifiers: .command),
                          isEnabled: !selection.isEmpty) {
                model.revealInFinder(ids: model.tableSelection)
            },
            ModuleCommand("Copy Path", shortcut: KeyboardShortcut("c", modifiers: [.command, .shift]),
                          isEnabled: !selection.isEmpty) {
                model.copyPaths(ids: model.tableSelection)
            },
            ModuleCommand("Check", isEnabled: !selection.isEmpty && !model.isReclaiming) {
                model.setChecked(true, ids: model.tableSelection)
            },
            ModuleCommand("Uncheck", isEnabled: !selection.isEmpty && !model.isReclaiming) {
                model.setChecked(false, ids: model.tableSelection)
            },
            ModuleCommand("Add to Watched Folders", isEnabled: model.canWatchSelection(ids: selection)) {
                model.addToWatchedFolders(ids: model.tableSelection)
            },
            ModuleCommand("Exclude from Future Scans", shortcut: KeyboardShortcut("e", modifiers: .command),
                          isEnabled: !selection.isEmpty && !model.isReclaiming) {
                model.exclude(ids: model.tableSelection)
            },
        ]
    }
}
