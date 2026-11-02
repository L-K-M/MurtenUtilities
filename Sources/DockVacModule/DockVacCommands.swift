import DockVacCore
import MurtenModuleKit
import SwiftUI

/// The standalone app's Connection, View, Cleanup and Help menu items, with their
/// shortcuts, for the suite's Tool menu. The suite owns the app, Edit and Window menus;
/// full screen comes with the suite's window.
@MainActor
enum DockVacCommands {
  static func make(for controller: AppController, state: ChromeState) -> [ModuleCommand] {
    [
      // View
      ModuleCommand(
        "Rescan Docker", id: "rescan", shortcut: KeyboardShortcut("r", modifiers: .command),
        isEnabled: state.canRescan
      ) { controller.rescan(nil) },
      ModuleCommand(
        "Back to Overview", id: "back", shortcut: KeyboardShortcut(.upArrow, modifiers: .command),
        isEnabled: state.canGoBack
      ) { controller.goBack(nil) },
      ModuleCommand(
        "Show Everything", id: "show-everything",
        shortcut: KeyboardShortcut("1", modifiers: .command), isEnabled: state.canFilter
      ) { controller.showEverything(nil) },
      ModuleCommand(
        "Show Reclaimable Only", id: "show-reclaimable",
        shortcut: KeyboardShortcut("2", modifiers: .command), isEnabled: state.canFilter
      ) { controller.showReclaimable(nil) },

      // Connection
      ModuleCommand(
        "Connect via SSH…", id: "connect-ssh", shortcut: KeyboardShortcut("k", modifiers: .command),
        isEnabled: state.canChangeConnection
      ) { controller.connectViaSSH(nil) },
      ModuleCommand(
        "Use Local Docker", id: "use-local", isEnabled: state.canChangeConnection
      ) { controller.useLocalDocker(nil) },

      // Cleanup
      ModuleCommand(
        state.selectedIsInBasket
          ? "Remove Selected Item from Cleanup" : "Add Selected Item to Cleanup",
        id: "toggle-selected", shortcut: KeyboardShortcut("a", modifiers: [.command, .shift]),
        isEnabled: state.canToggleSelected
      ) { controller.toggleSelectedInBasket(nil) },
      ModuleCommand(
        "Add Dangling Images and Build Cache", id: "add-safe",
        shortcut: KeyboardShortcut("d", modifiers: [.command, .shift]), isEnabled: state.canAddSafe
      ) { controller.addSafeItems(nil) },
      ModuleCommand(
        "Clear Cleanup List", id: "clear", isEnabled: state.canClearBasket
      ) { controller.clearBasketAction(nil) },
      ModuleCommand(
        AutomaticCleanupLevel.safe.menuTitle + "…", id: "clean-up-safe",
        shortcut: KeyboardShortcut("k", modifiers: [.command, .shift]),
        isEnabled: state.canCleanUpSafe
      ) { controller.automaticCleanupSafe(nil) },
      ModuleCommand(
        AutomaticCleanupLevel.thorough.menuTitle + "…", id: "clean-up-thorough",
        shortcut: KeyboardShortcut("k", modifiers: [.command, .shift, .option]),
        isEnabled: state.canCleanUpThorough
      ) { controller.automaticCleanupThorough(nil) },
      ModuleCommand(
        "Review and Remove…", id: "review", shortcut: KeyboardShortcut(.return, modifiers: .command),
        isEnabled: state.canReview
      ) { controller.reviewAndRemoveAction(nil) },

      // Help
      ModuleCommand("DockVac on GitHub", id: "help") { controller.openHelp(nil) },
    ]
  }
}
