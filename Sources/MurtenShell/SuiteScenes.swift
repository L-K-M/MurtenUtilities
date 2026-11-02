import AppKit
import SwiftUI
import MurtenCore
import MurtenModuleKit

/// The suite's two faces plus Settings, for the executable's `App`:
/// one home window, an opt-in menu-bar companion.
public struct SuiteScenes: Scene {
    public static let homeWindowID = "home"

    @Bindable private var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some Scene {
        // A single window: one home, one pane at a time. openWindow(id:)
        // brings it forward instead of stacking copies.
        Window("Murten Utilities", id: Self.homeWindowID) {
            RootView(model: model)
        }
        .defaultSize(width: 1040, height: 720)
        .commands {
            ToolCommands()
            // One home window; "New Window" would only duplicate it.
            CommandGroup(replacing: .newItem) {}
        }

        // Modules' auxiliary windows (a test pad, a job log), one per request.
        WindowGroup(id: ModuleWindowRequest.windowGroupID, for: ModuleWindowRequest.self) { $request in
            if let request, let content = model.window(for: request) {
                content.defaultAppStorage(model.defaults(for: request.moduleID))
            }
        }

        Settings {
            SettingsView(model: model)
        }

        // Resident mode governs the menu extra; it is off by default and
        // independent of launch at login (docs/architecture.md, Resident mode).
        MenuBarExtra(isInserted: residentBinding) {
            MenuBarPanel(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        // A panel rather than a menu, so modules can show live instruments.
        .menuBarExtraStyle(.window)
    }

    private var residentBinding: Binding<Bool> {
        Binding(get: { model.settings.residentMode == .on },
                // Removing the item from the menu bar (⌘-drag out) turns the
                // companion off, so the setting never lies.
                set: { model.settings.residentMode = $0 ? .on : .off })
    }
}

/// App-level behavior SwiftUI scenes cannot express: the light appearance
/// and the quit guard for work in progress.
@MainActor
public final class SuiteAppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the app's initializer; the adaptor creates the delegate itself.
    public static weak var model: AppModel?

    public override init() {
        super.init()
    }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        // Light only (docs/ui-direction.md): Info.plist's key plus the
        // documented appearance override, as Lucerne does.
        NSApp.appearance = NSAppearance(named: .aqua)
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Background work starts with the app, not with the window, so the
        // companion works while the window is closed.
        Task { await Self.model?.start() }
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let warnings = Self.model?.interruptionWarnings(), !warnings.isEmpty else { return .terminateNow }

        // A destructive confirmation, the one case the suite uses an alert.
        let alert = NSAlert()
        alert.messageText = "Quit while work is in progress?"
        alert.informativeText = warnings.joined(separator: "\n")
        alert.addButton(withTitle: "Keep Working")
        alert.addButton(withTitle: "Quit Anyway")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}

/// The focused pane's commands, with their shortcuts, in a Tool menu.
struct ToolCommands: Commands {
    @FocusedValue(\.moduleCommands) private var commands

    var body: some Commands {
        CommandMenu("Tool") {
            if let commands, !commands.isEmpty {
                ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                    if index > 0, commands[index - 1].group != command.group {
                        Divider()
                    }
                    ToolCommandItem(command: command)
                }
            } else {
                Text("Open a tool to see its commands")
            }
        }
    }
}

/// One Tool-menu item: a button, or a toggle when it carries a checkmark.
private struct ToolCommandItem: View {
    let command: ModuleCommand

    var body: some View {
        item
            .keyboardShortcut(command.shortcut)
            .disabled(!command.isEnabled)
            .help(command.help ?? "")
    }

    @ViewBuilder private var item: some View {
        switch command.checkState {
        case .none:
            Button(command.title) { command.action() }
        case .checked, .unchecked:
            // Toggling runs the command; the pane publishes the new state.
            Toggle(command.title, isOn: Binding(get: { command.checkState == .checked },
                                                set: { _ in command.action() }))
        }
    }
}
