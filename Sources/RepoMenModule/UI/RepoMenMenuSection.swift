import SwiftUI
import RepoMenCore

/// RepoMen's part of the suite's menu-bar companion, replacing the standalone
/// app's own menu-bar extra: whether auto-trash is armed, where, its last pass,
/// and a switch to turn it off. Background-check findings appear in the
/// companion's suggestion list, not here.
struct RepoMenMenuSection: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var autoTrash: AutoTrashController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            let armed = autoTrash.armedFolders
            if armed.isEmpty {
                Text("Auto-trash is off.")
                    .foregroundStyle(.secondary)
            } else {
                Label {
                    Text("Auto-trash armed: \(folderList(armed))")
                } icon: {
                    Image(systemName: "trash")
                }
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(autoTrash.isAllowedToRun ? Color.secondary : Color.orange)
                Button("Turn Off Auto-Trash") { autoTrash.disarmAll() }
                    .controlSize(.small)
                    .help("Disarm every watched folder. Watching and suggestions continue.")
            }
            if preferences.lifetimeReclaimedBytes > 0 {
                Text("Lifetime: \(Format.bytes(preferences.lifetimeReclaimedBytes)) repossessed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func folderList(_ folders: [WatchedFolder]) -> String {
        let names = folders.prefix(3).map { Format.abbreviatePath($0.path) }
        let more = folders.count > 3 ? " and \(folders.count - 3) more" : ""
        return names.joined(separator: ", ") + more
    }

    private var statusLine: String {
        if autoTrash.isRunning { return "Moving stale artifacts to the Trash…" }
        if !autoTrash.isAllowedToRun { return "Paused: RepoMen's background check is off." }
        guard let run = preferences.lastWatchRun else { return "First pass runs shortly." }
        let age = Format.age(run.date)
        return run.reclaimedCount == 0
            ? "Last pass \(age): nothing stale."
            : "Last pass \(age): \(Format.bytes(run.reclaimedBytes)) moved to the Trash."
    }
}
