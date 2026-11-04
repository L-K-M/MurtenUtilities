import AppKit
import SwiftUI
import RepoMenCore

/// Settings → Watch: the folders RepoMen watches. Each has its own idle threshold.
/// The suite's background check reports what is stale there; auto-trash, armed
/// folder by folder, moves it to the Trash on its own schedule.
struct WatchSettingsView: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var autoTrash: AutoTrashController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("""
                Developer Cleanup's background check looks at your scan folders and these watched \
                folders every 6 hours and suggests a clean-up once artifacts idle past a \
                folder's threshold reach 5 GB. Turn it on in Settings › Background Checks. \
                It never removes anything, and it skips folders in Desktop, Documents, \
                Downloads, iCloud Drive or on external volumes.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Watched folders:")
                .padding(.top, 6)
            List {
                ForEach($preferences.watchedFolders) { $folder in
                    WatchedFolderRow(folder: $folder, isProtected: autoTrash.isProtected(folder))
                }
                .onDelete { preferences.watchedFolders.remove(atOffsets: $0) }
            }
            .frame(minHeight: 120)
            HStack {
                Button("Add Folder…") { addFolder() }
                Menu("Watch a Scan Folder") {
                    ForEach(unwatchedScanRoots, id: \.self) { root in
                        Button(Format.abbreviatePath(root)) { watch(root) }
                    }
                }
                .disabled(unwatchedScanRoots.isEmpty)
                .help("One tap to watch a folder you already scan")
            }

            Divider()
                .padding(.vertical, 4)

            Text("""
                Auto-trash: in folders you arm, stale artifacts go to the Trash (never a \
                permanent delete) every 6 hours, each re-verified like a manual reclaim, and \
                the pane's auto-trash log lists them. It runs only while Murten Utilities \
                stays in the menu bar with Developer Cleanup's background check on. Folders in \
                Desktop, Documents, Downloads, iCloud Drive or on external volumes cannot be \
                armed, because macOS would ask for access with no window in front; scan \
                them in the pane instead.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if autoTrash.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(lastRunText)
                    .font(.caption)
                    .foregroundStyle(autoTrash.armedFolders.isEmpty || autoTrash.isAllowedToRun
                                     ? Color.secondary : Color.orange)
            }
        }
        .padding(20)
    }

    private var unwatchedScanRoots: [String] {
        let watched = Set(preferences.watchedFolders.map(\.path))
        return preferences.scanRoots.filter { !watched.contains($0) }
    }

    private var lastRunText: String {
        let armed = autoTrash.armedFolders.count
        guard armed > 0 else { return "No folder is armed for auto-trash." }
        let folders = armed == 1 ? "1 folder" : "\(armed) folders"
        if !autoTrash.isAllowedToRun {
            return "Armed in \(folders), paused until the menu bar companion and Developer Cleanup's background check are on."
        }
        guard let run = preferences.lastWatchRun else {
            return "Armed in \(folders). The first pass runs shortly, then every 6 hours."
        }
        let age = Format.age(run.date)
        return run.candidateCount == 0
            ? "Armed in \(folders). Last pass \(age): nothing stale."
            : "Armed in \(folders). Last pass \(age): repossessed \(Format.bytes(run.reclaimedBytes)) across \(run.reclaimedCount) items."
    }

    private func watch(_ path: String) {
        preferences.watchFolder(path: path)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Watch"
        panel.message = "Choose folders for Developer Cleanup to keep clean automatically"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { watch(url.path) }
    }
}

/// One watched folder: watch on/off, its idle threshold, and its auto-trash arm.
private struct WatchedFolderRow: View {
    @Binding var folder: WatchedFolder
    let isProtected: Bool

    var body: some View {
        let name = Format.abbreviatePath(folder.path)
        HStack(spacing: 8) {
            Toggle("Watch \(name)", isOn: $folder.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help("Pause watching this folder without removing it")
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
            if isProtected {
                Image(systemName: "lock")
                    .foregroundStyle(.secondary)
                    .help("macOS protects this location with a privacy prompt, so background checks and auto-trash skip it. Scan it in the pane.")
                    .accessibilityLabel("Privacy-protected location")
            }
            Spacer()
            Stepper(value: $folder.maxIdleDays, in: 1...365) {
                Text("\(folder.maxIdleDays) d")
                    .monospacedDigit()
            }
            .help("Artifacts idle longer than this count as stale")
            .accessibilityLabel("Idle threshold for \(name)")
            .accessibilityValue("\(folder.maxIdleDays) days")
            Toggle("Auto-trash", isOn: $folder.autoTrashArmed)
                .toggleStyle(.checkbox)
                // A protected folder can be disarmed, never armed.
                .disabled(isProtected && !folder.autoTrashArmed)
                .help(isProtected
                      ? "Auto-trash cannot run in a privacy-protected location."
                      : "Move this folder's stale artifacts to the Trash automatically")
                .accessibilityLabel("Auto-trash \(name)")
        }
    }
}
