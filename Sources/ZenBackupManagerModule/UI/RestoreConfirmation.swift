import SwiftUI

struct RestoreConfirmation: View {
    let backup: BackupRecord
    let profile: ZenProfile
    let current: SessionPreview?
    let restore: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var running = ZenRuntime.isRunning
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Restore this moment?").font(.title2.bold())
                    Text(backup.date.formatted(date: .complete, time: .shortened)).foregroundStyle(.secondary)
                }
            }
            Divider()
            LabeledContent("Profile", value: profile.name)
            LabeledContent("Tabs", value: "\(backup.preview?.tabs.count ?? 0)")
            LabeledContent("Spaces", value: "\(backup.preview?.spaces.count ?? 0)")
            if let current, let preview = backup.preview {
                let diff = preview.difference(from: current)
                Text("This snapshot adds \(diff.added) tabs and removes \(diff.removed) compared with the current saved session.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Label("Your current session files will be saved first. You can undo this restore from the toolbar.", systemImage: "shield.lefthalf.filled")
                .font(.callout).padding(14).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            if backup.preview?.tabs.isEmpty == true {
                Label("This backup contains no tabs.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            if running {
                HStack {
                    Label("Quit Zen before restoring.", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                    Spacer()
                    Button("Quit Zen") { ZenRuntime.quit() }
                }
                Text("Zen may ask you to finish downloads or confirm closing. Restore becomes available once it has quit.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Label("Zen is closed and ready to restore.", systemImage: "checkmark.circle").foregroundStyle(.green)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Restore Backup", action: restore).buttonStyle(.borderedProminent).tint(.teal).disabled(running)
            }
        }.padding(28).frame(width: 500)
            .onReceive(timer) { _ in running = ZenRuntime.isRunning }
    }
}
