import AppKit
import SwiftUI
import MurtenCore

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

        Settings {
            SettingsView(model: model)
        }

        // Resident mode governs the menu extra; it is off by default and
        // independent of launch at login (docs/architecture.md, Resident mode).
        MenuBarExtra(isInserted: residentBinding) {
            MenuBarContent(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)
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
