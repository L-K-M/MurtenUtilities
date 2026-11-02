import SwiftUI

struct BackupSidebar: View {
    @ObservedObject var model: AppModel
    private var maximumTabs: Int { max(1, model.records.compactMap { $0.preview?.tabs.count }.max() ?? 1) }
    private var days: [Date] {
        Set(model.visibleRecords.filter { $0.kind != .current }.map { Calendar.current.startOfDay(for: $0.date) }).sorted(by: >)
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("PROFILE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Picker("Profile", selection: $model.profileID) {
                    ForEach(model.profiles) { profile in
                        Text(profile.name + (profile.isDefault ? " · Default" : "")).tag(Optional(profile.id))
                    }
                }.labelsHidden().disabled(model.busy)
                HStack {
                    Button("Choose Folder…") { model.chooseProfile() }.buttonStyle(.link).disabled(model.busy)
                    Spacer()
                    if let profile = model.profile {
                        Button { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: profile.directory.path) } label: { Image(systemName: "folder") }
                            .buttonStyle(.plain).help("Show profile in Finder")
                    }
                }
            }.padding(16)
            Divider()
            List(selection: $model.selectedID) {
                let current = model.visibleRecords.filter { $0.kind == .current }
                if !current.isEmpty {
                    Section("On this Mac") {
                        ForEach(current) { row($0) }
                    }
                }
                ForEach(days, id: \.self) { day in
                    Section(day.formatted(date: .abbreviated, time: .omitted)) {
                        ForEach(model.visibleRecords.filter { $0.kind != .current && Calendar.current.isDate($0.date, inSameDayAs: day) }) { row($0) }
                    }
                }
            }.listStyle(.sidebar)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Legacy backups", isOn: $model.showLegacy)
                Toggle("Safety copies", isOn: $model.showSafety)
                Text("\(model.visibleRecords.count) snapshots · Stored locally")
                    .font(.caption).foregroundStyle(.secondary)
            }.font(.callout).toggleStyle(.checkbox).padding(16)
        }
    }

    private func row(_ backup: BackupRecord) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: backup.kind == .current ? "macwindow" : backup.kind == .safety ? "shield.lefthalf.filled" : "clock")
                    .foregroundStyle(backup.problem == nil ? Color.teal : Color.orange)
                Text(backup.kind == .current ? "Current state" : backup.date.formatted(date: .omitted, time: .shortened)).fontWeight(.medium)
                Spacer()
                if let preview = backup.preview { Text(preview.tabs.count.formatted()).monospacedDigit().fontWeight(.semibold) }
                else { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            if let preview = backup.preview {
                HStack {
                    Text("\(preview.spaces.count) spaces · \(backup.kind == .current ? preview.format.rawValue : backup.kind.rawValue)")
                    Spacer()
                    Text("tabs")
                }.font(.caption).foregroundStyle(.secondary)
                GeometryReader { geometry in
                    Capsule().fill(Color.teal.opacity(0.14))
                    Capsule().fill(Color.teal.opacity(0.65)).frame(width: max(3, geometry.size.width * Double(preview.tabs.count) / Double(maximumTabs)))
                }.frame(height: 3).accessibilityHidden(true)
            } else { Text("Unreadable backup").font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 6).tag(backup.id)
            .help(backup.file.lastPathComponent)
    }
}
