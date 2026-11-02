import SwiftUI
import MurtenCore

/// What the suite noticed, above the tools. Every row opens its module's
/// pane; nothing here repairs anything.
struct SuggestionFeed: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggestions")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            if model.settings.residentMode == .off {
                Text("Background checks are off. Turn them on in Settings to have Murten Utilities notice when a tool would help.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if model.suggestions.isEmpty {
                Text("Nothing needs your attention.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.suggestions) { suggestion in
                    SuggestionRow(model: model, suggestion: suggestion)
                }
            }
        }
    }
}

struct SuggestionRow: View {
    let model: AppModel
    let suggestion: Suggestion

    private var moduleName: String {
        model.module(suggestion.moduleID)?.name ?? suggestion.moduleID
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: model.module(suggestion.moduleID)?.systemImage ?? "lightbulb")
                .font(.title3)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.title)
                    .font(.body.weight(.semibold))
                Text(suggestion.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .stale(let since) = suggestion.freshness {
                    Label("Could not re-check since \(since.formatted(date: .abbreviated, time: .shortened)); this may be outdated.",
                          systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Open \(moduleName)") { _ = model.open(suggestion.route) }
            Menu {
                ForEach(SnoozeDuration.allCases) { duration in
                    Button(duration.title) { Task { await model.snooze(suggestion, for: duration) } }
                }
                Divider()
                Button("Dismiss") { Task { await model.dismiss(suggestion) } }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More actions for \(suggestion.title)")
        }
        .padding(10)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(moduleName) suggestion: \(suggestion.title)")
        .accessibilityAction(named: "Open \(moduleName)") { _ = model.open(suggestion.route) }
        .accessibilityAction(named: "Snooze for a day") { Task { await model.snooze(suggestion, for: .oneDay) } }
        .accessibilityAction(named: "Dismiss") { Task { await model.dismiss(suggestion) } }
    }
}
