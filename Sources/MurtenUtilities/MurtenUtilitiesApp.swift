import SwiftUI
import MurtenCore

@main
struct MurtenUtilitiesApp: App {
    var body: some Scene {
        // The home window: the Norton-style grid of tools.
        WindowGroup("Murten Utilities", id: "home") {
            HomeView()
        }

        // The resident face. MenuBarExtra alone does not launch at login —
        // that stays an explicit opt-in via SMAppService (see PLAN.md).
        MenuBarExtra("Murten Utilities", systemImage: "wrench.and.screwdriver") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)
    }
}
