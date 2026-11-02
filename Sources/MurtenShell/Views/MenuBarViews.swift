import AppKit
import SwiftUI
import MurtenCore

/// The resident face's menu: suggestions with their actions, then a way
/// into the app. Only inserted while resident mode is on.
struct MenuBarContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if model.suggestions.isEmpty {
            Text("Nothing needs your attention")
        } else {
            ForEach(model.suggestions) { suggestion in
                Menu(menuTitle(for: suggestion)) {
                    Button("Open \(model.module(suggestion.moduleID)?.name ?? suggestion.moduleID)") {
                        bringForward(suggestion.route)
                    }
                    ForEach(SnoozeDuration.allCases) { duration in
                        Button(duration.title) { Task { await model.snooze(suggestion, for: duration) } }
                    }
                    Button("Dismiss") { Task { await model.dismiss(suggestion) } }
                }
            }
        }

        Divider()
        Button("Open Murten Utilities") { bringForward(nil) }
            .keyboardShortcut("o")
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Murten Utilities") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func menuTitle(for suggestion: Suggestion) -> String {
        if case .stale = suggestion.freshness { return "\(suggestion.title) (may be outdated)" }
        return suggestion.title
    }

    private func bringForward(_ route: ModuleRoute?) {
        model.present(route)
        openWindow(id: SuiteScenes.homeWindowID)
        NSApp.activate()
    }
}

/// The status item: the suite's icon plus a count when something needs
/// attention. It also opens the home window for requests that arrive while
/// no window exists, such as a clicked notification.
struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let count = model.suggestions.count
        HStack(spacing: 2) {
            Image(systemName: "wrench.and.screwdriver")
            if count > 0 { Text("\(count)") }
        }
        .accessibilityLabel(count == 0 ? "Murten Utilities" : "Murten Utilities, \(count) suggestions")
        .onChange(of: model.windowRequests) {
            openWindow(id: SuiteScenes.homeWindowID)
            NSApp.activate()
        }
    }
}
