import SwiftUI
import AppKit

/// The menu-bar face: a way back to the home window today, and later the
/// suggestion feed and watcher controls (see docs/architecture.md). It is
/// deliberately quiet — no badge, no notifications — until a user opts in.
struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Murten Utilities") {
            openWindow(id: "home")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Divider()
        Text("No suggestions yet")
        Divider()
        Button("Quit Murten Utilities") {
            NSApplication.shared.terminate(nil)
        }
    }
}
