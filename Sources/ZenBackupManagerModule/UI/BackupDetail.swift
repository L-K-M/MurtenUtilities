import SwiftUI

struct BackupDetail: View {
    let backup: BackupRecord
    let current: SessionPreview?
    let restore: () -> Void
    @State private var search = ""
    @State private var spaceID = "all"
    @State private var onlyPinned = false
    @State private var selectedTab: String?

    private var tabs: [SessionPreview.Tab] {
        (backup.preview?.tabs ?? []).filter { tab in
            (spaceID == "all" || (spaceID == "essential" ? tab.essential : tab.spaceID == spaceID)) &&
            (!onlyPinned || tab.pinned || tab.essential) &&
            (search.isEmpty || tab.title.localizedCaseInsensitiveContains(search) || tab.url.localizedCaseInsensitiveContains(search))
        }
    }
    private func spaceName(_ tab: SessionPreview.Tab) -> String {
        if tab.essential { return "Essentials" }
        return backup.preview?.spaces.first { $0.id == tab.spaceID }?.name ?? "Unassigned"
    }

    var body: some View {
        if let preview = backup.preview {
            VStack(alignment: .leading, spacing: 0) {
                header(preview).padding(24)
                Divider()
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search titles or URLs", text: $search).textFieldStyle(.plain)
                        .accessibilityLabel("Search titles or URLs")
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
                    }
                    Toggle("Pinned only", isOn: $onlyPinned).toggleStyle(.checkbox)
                }.padding(.horizontal, 24).padding(.vertical, 14)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("All tabs", id: "all", count: preview.tabs.count)
                        if preview.tabs.contains(where: \.essential) {
                            chip("Essentials", id: "essential", count: preview.tabs.filter(\.essential).count)
                        }
                        ForEach(preview.spaces) { space in
                            chip("\(space.icon.count < 5 ? space.icon : "") \(space.name)", id: space.id,
                                count: preview.tabs.filter { $0.spaceID == space.id }.count)
                        }
                    }.padding(.horizontal, 24)
                }.padding(.bottom, 16)
                Divider()
                Table(tabs, selection: $selectedTab) {
                    TableColumn("Tab") { tab in
                        HStack(spacing: 10) {
                            Image(systemName: tab.essential ? "star.fill" : tab.pinned ? "pin.fill" : "globe")
                                .foregroundStyle(tab.essential ? Color.orange : Color.teal).frame(width: 16)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tab.title).lineLimit(1)
                                Text(tab.host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }.padding(.vertical, 5)
                        }.help(tab.url)
                            .contextMenu {
                                Button("Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(tab.url, forType: .string) }
                            }
                    }.width(min: 260, ideal: 420)
                    TableColumn("Space") { tab in Text(spaceName(tab)).foregroundStyle(.secondary) }.width(min: 100, ideal: 140, max: 200)
                }
                if tabs.isEmpty { Text("No tabs match these filters.").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding() }
                Divider()
                HStack {
                    Text("\(tabs.count.formatted()) of \(preview.tabs.count.formatted()) tabs")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(backup.bytes), countStyle: .file))
                    Button("Show File") { NSWorkspace.shared.activateFileViewerSelecting([backup.file]) }.buttonStyle(.link)
                }.font(.caption).foregroundStyle(.secondary).padding(14)
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.doc").font(.system(size: 42)).foregroundStyle(.orange)
                Text("This backup can't be read").font(.title2.bold())
                Text(backup.problem ?? "Unknown format").foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text(backup.file.lastPathComponent).font(.caption.monospaced()).textSelection(.enabled)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([backup.file]) }
            }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ preview: SessionPreview) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(backup.kind == .current ? "CURRENT STATE" : "SAVED MOMENT")
                        .font(.caption.weight(.semibold)).tracking(1.3).foregroundStyle(.teal)
                    Text(backup.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 25, weight: .semibold, design: .rounded))
                    Text(backup.file.lastPathComponent).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 32, weight: .light)).foregroundStyle(.teal.opacity(0.6))
            }
            HStack(spacing: 12) {
                metric(preview.tabs.count, "Tabs", "rectangle.stack")
                metric(preview.spaces.count, "Spaces", "square.grid.2x2")
                metric(preview.pinnedCount, "Pinned & essentials", "pin")
                metric(preview.folderCount, "Folders", "folder")
            }
            if let current, backup.kind != .current {
                let diff = preview.difference(from: current)
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right")
                    Text("Compared with current: \(diff.added) tabs added · \(diff.removed) tabs removed")
                }.font(.callout).foregroundStyle(.secondary)
            }
            if preview.format == .firefox {
                Label("Legacy restore replaces the session and lets Zen migrate it at launch.", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func metric(_ value: Int, _ label: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Image(systemName: icon).foregroundStyle(.teal); Spacer(); Text(value.formatted()).font(.title2.weight(.semibold)).monospacedDigit() }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.05)))
    }

    private func chip(_ title: String, id: String, count: Int) -> some View {
        Button { spaceID = id } label: {
            HStack(spacing: 6) { Text(title.trimmingCharacters(in: .whitespaces)); Text(count.formatted()).foregroundStyle(.secondary) }
                .font(.callout).padding(.horizontal, 12).padding(.vertical, 7)
                .background(spaceID == id ? Color.teal.opacity(0.15) : Color.primary.opacity(0.04), in: Capsule())
                .overlay(Capsule().strokeBorder(spaceID == id ? Color.teal.opacity(0.5) : .clear))
        }.buttonStyle(.plain).accessibilityAddTraits(spaceID == id ? .isSelected : [])
    }
}
