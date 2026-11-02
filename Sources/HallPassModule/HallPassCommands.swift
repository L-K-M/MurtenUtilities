import AppKit
import SwiftUI
import HallPassCore
import MurtenModuleKit

enum WorkspaceCommand: String {
    case add, edit, remove, review, load, discard, reset, preview
    case importBackup, exportBackup, backups, inspector, search, wifi, ethernet, help
}

/// The standalone app's menu commands. The suite owns the menu bar, so the
/// pane publishes them to the Tool menu while it is focused. Window, full
/// screen and sidebar commands are the shell's; toggles carry their state
/// in the title because a module command has no checkmark.
@MainActor
struct WorkspaceActions {
    let model: HallPassModel
    let available: Bool
    let selectionCount: Int
    let selectionIsActive: Bool
    let showsInspector: Bool
    let interface: NetworkInterface
    let perform: (WorkspaceCommand) -> Void

    var canEdit: Bool { available && model.canEdit }
    var canEditSelection: Bool { canEdit && selectionIsActive && selectionCount == 1 }
    var canRemove: Bool { canEdit && selectionIsActive && selectionCount > 0 }

    var moduleCommands: [ModuleCommand] {
        [
            command("Add Network Range…", .add, KeyboardShortcut("n"), enabled: canEdit),
            command("Edit IP Range…", .edit, KeyboardShortcut(.return, modifiers: .command), enabled: canEditSelection),
            command("Remove Selected IP Ranges", .remove, enabled: canRemove),
            command(model.isLoaded ? "Reload Configuration…" : "Load Configuration…", .load, KeyboardShortcut("l"),
                    enabled: available),
            command("Review Changes…", .review, KeyboardShortcut("s"), enabled: available && model.canReview),
            command("Discard Changes…", .discard, enabled: canEdit && model.isDirty),
            command("Import Backup…", .importBackup, KeyboardShortcut("o"), enabled: canEdit),
            command("Export Saved State…", .exportBackup, KeyboardShortcut("e", modifiers: [.command, .shift]),
                    enabled: available && model.isLoaded),
            command("Open Backups Folder", .backups, enabled: available && !model.isDemo),
            command("Remove All Exemptions…", .reset, enabled: canEdit && model.draft != NetworkConfiguration()),
            command("Search IP Ranges", .search, KeyboardShortcut("f"), enabled: available && model.isLoaded),
            command(showsInspector ? "Hide Information" : "Show Information", .inspector,
                    KeyboardShortcut("i", modifiers: [.command, .option]), enabled: available && model.isLoaded),
            command("Show Wi-Fi", .wifi, KeyboardShortcut("1"), enabled: available && interface != .wifi),
            command("Show Ethernet", .ethernet, KeyboardShortcut("2"), enabled: available && interface != .ethernet),
            command(model.isDemo ? "End Preview…" : "Start Preview", .preview,
                    enabled: available && (!model.isLoaded || model.isDemo)),
            command("HallPass Help", .help, enabled: available),
            ModuleCommand("Open Apple Documentation", id: "hallpass.documentation") {
                _ = NSWorkspace.shared.open(HallPassHelp.appleDocumentation)
            }
        ]
    }

    private func command(_ title: String, _ command: WorkspaceCommand, _ shortcut: KeyboardShortcut? = nil,
                         enabled: Bool) -> ModuleCommand {
        let perform = perform
        return ModuleCommand(title, id: "hallpass.\(command.rawValue)", shortcut: shortcut, isEnabled: enabled) {
            perform(command)
        }
    }
}
