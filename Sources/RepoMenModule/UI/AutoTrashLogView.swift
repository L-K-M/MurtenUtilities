import AppKit
import SwiftUI
import RepoMenCore

/// Sidebar → Watch → Auto-trash log: everything armed auto-trash moved to the
/// Trash, and what it left alone and why, newest first. Items can be put back
/// from the Trash; the log says where they came from.
struct AutoTrashLogView: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var autoTrash: AutoTrashController
    @State private var confirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            if preferences.autoTrashLog.isEmpty {
                placeholder
            } else {
                Table(preferences.autoTrashLog) {
                    TableColumn("When") { entry in
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            .monospacedDigit()
                    }
                    .width(min: 120, ideal: 150)
                    TableColumn("Item") { entry in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.label)
                            Text(Format.abbreviatePath(entry.path))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .help(entry.path)
                    }
                    TableColumn("Size") { entry in
                        Text(Format.bytes(entry.bytes))
                            .monospacedDigit()
                    }
                    .width(min: 70, ideal: 80)
                    TableColumn("Result") { entry in
                        resultText(entry.result)
                    }
                    .width(min: 120, ideal: 200)
                }
            }
            Divider()
            footer
        }
        .confirmationDialog("Clear the auto-trash log?", isPresented: $confirmingClear) {
            Button("Clear Log", role: .destructive) { preferences.autoTrashLog = [] }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only the log is cleared. Items already in the Trash stay there.")
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(autoTrash.armedFolders.isEmpty
                 ? "Auto-trash is off. Arm it for a watched folder in Settings › Developer Cleanup › Watch."
                 : "Auto-trash has not moved anything yet.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func resultText(_ result: AutoTrashLogEntry.Result) -> some View {
        switch result {
        case .trashed:
            Text("Moved to the Trash")
        case .skipped(let reason):
            Text("Left alone: \(reason)")
                .foregroundStyle(.orange)
                .help(reason)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button("Open Trash") { openTrash() }
                .controlSize(.small)
            Button("Clear Log…") { confirmingClear = true }
                .controlSize(.small)
                .disabled(preferences.autoTrashLog.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var statusText: String {
        let armed = autoTrash.armedFolders
        guard !armed.isEmpty else { return "No folder is armed for auto-trash." }
        let folders = armed.count == 1 ? "1 folder" : "\(armed.count) folders"
        if autoTrash.isRunning { return "Auto-trash is running in \(folders)…" }
        if !autoTrash.isAllowedToRun {
            return "Armed in \(folders), paused: auto-trash runs only while Murten Utilities stays in the menu bar with Developer Cleanup's background check on."
        }
        guard let run = preferences.lastWatchRun else { return "Armed in \(folders); the first pass runs shortly." }
        return "Armed in \(folders). Last pass \(Format.age(run.date)): \(Format.bytes(run.reclaimedBytes)) moved to the Trash."
    }

    private func openTrash() {
        guard let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first else { return }
        NSWorkspace.shared.open(trash)
    }
}
