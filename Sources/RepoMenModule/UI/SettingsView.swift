import AppKit
import SwiftUI
import RepoMenCore

/// RepoMen's tab in the suite's Settings: General / Folders / Watch / Rules. The
/// suite owns updates, the login item and the menu bar, so their tabs and
/// toggles are gone. The tab views are implementation details and live here.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            FoldersSettingsView()
                .tabItem { Label("Folders", systemImage: "folder") }
            WatchSettingsView()
                .tabItem { Label("Watch", systemImage: "eye") }
            RulesSettingsView()
                .tabItem { Label("Rules", systemImage: "checklist") }
        }
        .frame(width: 520)
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        Form {
            Toggle("Move reclaimed items to the Trash", isOn: $preferences.moveToTrash)
            Text(preferences.moveToTrash
                 ? "Reversible — drag items back out of the Trash if you change your mind."
                 : "Items are deleted immediately and cannot be recovered.")
                .font(.caption)
                .foregroundStyle(preferences.moveToTrash ? Color.secondary : Color.orange)

            Stepper(value: $preferences.idleDays, in: 1...365) {
                Text("Consider artifacts idle after \(preferences.idleDays) days")
            }
            Text("Used by the “Select idle” quick action in the pane, and as the threshold for newly watched folders.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Scan automatically when RepoMen opens", isOn: $preferences.scanAtLaunch)
        }
        .padding(20)
    }
}

private struct FoldersSettingsView: View {
    @EnvironmentObject private var preferences: Preferences
    @State private var selectedRoot: String?
    @State private var selectedExclusion: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scan these folders for project build artifacts:")
            List(selection: $selectedRoot) {
                ForEach(preferences.scanRoots, id: \.self) { root in
                    HStack(spacing: 6) {
                        Text(Format.abbreviatePath(root))
                        if isOutsideHome(root) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .help("Outside your home folder — findings here can be listed but never reclaimed")
                        }
                    }
                    .tag(root)
                }
            }
            .frame(minHeight: 110)
            if let warning = outsideHomeWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button("Add Folder…") { addRoots() }
                Button("Remove") {
                    preferences.scanRoots.removeAll { $0 == selectedRoot }
                    selectedRoot = nil
                }
                .disabled(selectedRoot == nil)
            }

            Divider()
                .padding(.vertical, 4)

            Text("Excluded paths (never suggested again):")
            List(selection: $selectedExclusion) {
                ForEach(preferences.excludedPaths, id: \.self) { path in
                    Text(Format.abbreviatePath(path)).tag(path)
                }
            }
            .frame(minHeight: 80)
            Button("Remove Exclusion") {
                preferences.excludedPaths.removeAll { $0 == selectedExclusion }
                selectedExclusion = nil
            }
            .disabled(selectedExclusion == nil)
        }
        .padding(20)
    }

    private func addRoots() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders to scan for build artifacts"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !preferences.scanRoots.contains(url.path) {
            preferences.scanRoots.append(url.path)
        }
    }

    /// Reclaiming is restricted to the home folder (PathGuards); a root elsewhere
    /// scans fine but every find would fail at reclaim time — say so up front, in the
    /// list, not in a post-confirmation error.
    private func isOutsideHome(_ root: String) -> Bool {
        let home = NSHomeDirectory()
        return root != home && !root.hasPrefix(home + "/")
    }

    private var outsideHomeWarning: String? {
        let count = preferences.scanRoots.filter(isOutsideHome).count
        guard count > 0 else { return nil }
        let folders = count == 1 ? "1 folder is" : "\(count) folders are"
        return "\(folders) outside your home folder — findings there can be listed but never reclaimed."
    }
}

private struct RulesSettingsView: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Uncheck a kind and RepoMen stops finding or suggesting it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(ArtifactCategory.allCases) { category in
                    GroupBox(category.label) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(kinds(in: category)) { kind in
                                Toggle(isOn: binding(for: kind)) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(kind.label)
                                        Text(kind.regenerationHint)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                    }
                }
            }
            .padding(20)
        }
        // Grow with the display instead of always scrolling inside a 440pt cap —
        // the rules list keeps gaining kinds.
        .frame(minHeight: 440, idealHeight: 560, maxHeight: 680)
    }

    private func kinds(in category: ArtifactCategory) -> [ArtifactKind] {
        ArtifactKind.allCases.filter { $0.category == category && $0 != .uvCache }
    }

    private func binding(for kind: ArtifactKind) -> Binding<Bool> {
        Binding(
            get: { preferences.isEnabled(kind) },
            set: { preferences.setEnabled($0, kind: kind) })
    }
}
