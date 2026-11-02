import AppKit
import SwiftUI
import MurtenCore

/// The resident face: what needs attention, each module's menu section
/// (instruments, armed automation), then a way into the app. Only inserted
/// while resident mode is on.
struct MenuBarPanel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Murten Utilities")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            if model.suggestions.isEmpty {
                Text("Nothing needs your attention.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.suggestions) { suggestion in
                    MenuSuggestionRow(model: model, suggestion: suggestion) { bringForward(suggestion.route) }
                }
            }

            ForEach(model.modulesWithMenuSections) { module in
                if let section = model.menuSection(for: module.id) {
                    Divider()
                    Text(module.name)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    section
                        .defaultAppStorage(model.defaults(for: module.id))
                }
            }

            Divider()
            HStack {
                Button("Open Murten Utilities") { bringForward(nil) }
                    .keyboardShortcut("o")
                Spacer()
                SettingsLink {
                    Label("Settings…", systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                }
                .keyboardShortcut(",")
                .help("Settings…")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit Murten Utilities", systemImage: "power")
                        .labelStyle(.iconOnly)
                }
                .keyboardShortcut("q")
                .help("Quit Murten Utilities")
            }
        }
        .padding(12)
        .frame(width: 360)
    }

    private func bringForward(_ route: ModuleRoute?) {
        model.present(route)
        openWindow(id: SuiteScenes.homeWindowID)
        NSApp.activate()
    }
}

private struct MenuSuggestionRow: View {
    let model: AppModel
    let suggestion: Suggestion
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(suggestion.title)
                .font(.body.weight(.semibold))
            Text(suggestion.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if case .stale = suggestion.freshness {
                Text("May be outdated: the last check failed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Open \(model.module(suggestion.moduleID)?.name ?? suggestion.moduleID)", action: open)
                Menu("Snooze") {
                    ForEach(SnoozeDuration.allCases) { duration in
                        Button(duration.title) { Task { await model.snooze(suggestion, for: duration) } }
                    }
                }
                .fixedSize()
                Button("Dismiss") { Task { await model.dismiss(suggestion) } }
            }
            .controlSize(.small)
        }
        .accessibilityElement(children: .contain)
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
