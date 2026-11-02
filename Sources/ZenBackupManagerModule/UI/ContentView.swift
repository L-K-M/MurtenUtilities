import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var confirmingRestore = false
    @State private var confirmingUndo = false

    var body: some View {
        NavigationSplitView {
            BackupSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 270, ideal: 310, max: 380)
        } detail: {
            VStack(spacing: 0) {
                if let notice = model.notice {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(notice).font(.callout)
                        Spacer()
                        Button("Open Zen") { model.openZen() }
                        Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss notice")
                    }.padding().background(.green.opacity(0.08))
                    Divider()
                }
                if model.busy {
                    VStack(spacing: 16) { ProgressView(); Text(model.progress).foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let backup = model.selected {
                    BackupDetail(backup: backup, current: model.current?.preview, restore: { confirmingRestore = true })
                        .id(backup.id)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 48, weight: .light)).foregroundStyle(.teal)
                        Text(model.profiles.isEmpty ? "Find your Zen backups" : "Choose a moment to return to")
                            .font(.title2.bold())
                        Text(model.profiles.isEmpty ? "Choose your Zen profile folder to browse saved tabs and spaces." : "Select a backup from the timeline to preview its tabs.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Choose Profile Folder…") { model.chooseProfile() }
                    }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle("Zen Backup Manager")
        .toolbar {
            ToolbarItemGroup {
                Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .help("Refresh backups (⌘R)").disabled(model.busy || model.profile == nil)
                Button { model.exportSelected() } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .help("Export selected backup").disabled(model.busy || model.selected?.preview == nil)
                Button { confirmingUndo = true } label: { Label("Undo Restore", systemImage: "arrow.uturn.backward") }
                    .help("Return to the latest safety copy").disabled(model.busy || model.lastSafety == nil)
                Button("Restore…", systemImage: "clock.arrow.circlepath") { confirmingRestore = true }
                    .disabled(model.busy || model.selected?.canRestore != true)
            }
        }
        .onChange(of: model.profileID) { model.notice = nil; model.refresh() }
        .sheet(isPresented: $confirmingRestore) {
            if let backup = model.selected, let profile = model.profile {
                RestoreConfirmation(backup: backup, profile: profile, current: model.current?.preview) {
                    confirmingRestore = false; model.restoreSelected()
                }
            }
        }
        .alert("Undo the last restore?", isPresented: $confirmingUndo) {
            Button("Cancel", role: .cancel) { }
            Button("Restore Previous State") { model.undoLastRestore() }
        } message: {
            Text("Quit Zen first. This will restore the exact session files saved before the last operation for this profile. The current files will also be saved as a safety copy.")
        }
        .alert("Couldn't complete the operation", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
