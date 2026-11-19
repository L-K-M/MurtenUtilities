import SwiftUI
import AppKit
import DoctorCore

// MARK: - Sidebar

/// The All permissions sidebar: the flag filters, then every permission
/// found, each with its count.
struct InventorySidebar: View {
    @EnvironmentObject private var inventory: InventoryStore

    var body: some View {
        List(selection: selection) {
            Section("Show") {
                ForEach(InventoryFilter.allCases) { filter in
                    SidebarCountRow(title: filter.title, symbol: Self.symbol(filter), count: inventory.inventory?.count(filter))
                        .tag(InventoryStore.Selection.filter(filter))
                }
            }
            if let counts = inventory.inventory?.serviceCounts, !counts.isEmpty {
                Section("Permissions") {
                    ForEach(counts, id: \.service.identifier) { item in
                        SidebarCountRow(title: item.service.title, symbol: serviceSymbol(item.service), count: item.count)
                            .tag(InventoryStore.Selection.service(item.service.identifier))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var selection: Binding<InventoryStore.Selection?> {
        Binding(get: { inventory.selection }, set: { if let value = $0 { inventory.selection = value } })
    }

    private static func symbol(_ filter: InventoryFilter) -> String {
        switch filter {
        case .all: return "square.grid.2x2"
        case .leftovers: return "trash"
        case .lookAlikes: return "person.2"
        case .broken: return "exclamationmark.triangle"
        case .highRisk: return "exclamationmark.shield"
        }
    }
}

private struct SidebarCountRow: View {
    let title: String
    let symbol: String
    let count: Int?

    var body: some View {
        HStack {
            Label(title, systemImage: symbol).lineLimit(1)
            Spacer(minLength: 6)
            if let count {
                Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Detail

/// Every recorded decision the sidebar selection and the search leave,
/// grouped by app.
struct InventoryDetailView: View {
    @EnvironmentObject private var inventory: InventoryStore
    @EnvironmentObject private var doctor: DoctorStore
    @State private var resetRequest: InventoryResetRequest?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let notice = inventory.notice {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill").foregroundStyle(DoctorStyle.accent)
                    Text(notice).font(.callout).textSelection(.enabled)
                    Spacer(minLength: 10)
                    Button { inventory.notice = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss notice")
                }
                .padding(14)
                .background(DoctorStyle.accent.opacity(0.09))
                Divider()
            }
            content
        }
        .sheet(item: $resetRequest) { InventoryResetSheet(request: $0) }
        .task { if inventory.inventory == nil { await inventory.refresh() } }
    }

    private var busy: Bool { inventory.isReading || inventory.isResetting || doctor.isRepairing }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(inventory.selectionTitle).font(.title3.weight(.semibold))
                if let read = inventory.inventory {
                    Text("\(inventory.visibleEntries.count) of \(read.entries.count) entries · read \(read.readAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search apps or permissions", text: $inventory.search)
                    .textFieldStyle(.plain)
                    .frame(width: 190)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DoctorStyle.border))
            if !inventory.leftovers.isEmpty {
                Button("Clean Up Leftovers…") {
                    resetRequest = InventoryResetRequest(cleanup: inventory.leftovers)
                }
                .disabled(busy)
            }
            Button { inventory.copyReport() } label: { Label("Copy Report", systemImage: "doc.on.clipboard") }
                .help("Copy a plain-text report of every entry to the clipboard")
                .disabled(inventory.inventory == nil)
            Button { Task { await inventory.refresh() } } label: {
                if inventory.isReading {
                    ProgressView().controlSize(.small).frame(width: 16, height: 16)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .help("Read the privacy databases again")
            .disabled(busy)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var content: some View {
        if let read = inventory.inventory {
            List {
                if read.needsFullDiskAccess || read.userDatabaseUnavailable || read.sources.contains(where: Self.isFailure) {
                    Section { SourceBanners(inventory: read) }
                }
                if inventory.visibleGroups.isEmpty && !read.needsFullDiskAccess {
                    Text(read.entries.isEmpty ? "No permission entries were found." : "No entries match.")
                        .foregroundStyle(.secondary)
                }
                ForEach(inventory.visibleGroups) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            InventoryEntryRow(entry: entry, busy: busy) { resetRequest = request(for: entry) }
                        }
                    } header: {
                        ClientGroupHeader(group: group, busy: busy) { resetRequest = request(for: group) }
                    }
                }
            }
            .listStyle(.inset)
        } else {
            VStack(spacing: 10) {
                ProgressView()
                Text("Reading the privacy databases…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private static func isFailure(_ source: DatabaseSource) -> Bool {
        if case .failed = source.reading { return true }
        return false
    }

    /// The entry's whole reset: every entry of the same app and service,
    /// since `tccutil` resets them together.
    private func request(for entry: InventoryEntry) -> InventoryResetRequest {
        let all = inventory.inventory?.entries.filter { $0.clientKey == entry.clientKey } ?? [entry]
        return InventoryResetRequest(client: entry.client.name, entries: all,
                                     preselected: [InventoryResetRequest.unitID(entry)])
    }

    /// All of the app's entries, those on screen preselected.
    private func request(for group: PermissionInventory.ClientGroup) -> InventoryResetRequest {
        let all = inventory.inventory?.entries.filter { $0.clientKey == group.id } ?? group.entries
        return InventoryResetRequest(client: group.client.name, entries: all,
                                     preselected: Set(group.resettableEntries.map(InventoryResetRequest.unitID)))
    }
}

// MARK: - Sources

/// Why some entries may be missing: no Full Disk Access, the per-user
/// database out of reach on macOS 27, or a read that failed.
private struct SourceBanners: View {
    @EnvironmentObject private var store: InventoryStore
    let inventory: PermissionInventory

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if inventory.needsFullDiskAccess {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Full Disk Access is needed to read the privacy databases", systemImage: "lock.shield")
                        .font(.headline)
                    Text("macOS lets an app read the privacy databases only with Full Disk Access. Turn on Murten Utilities in System Settings › Privacy & Security › Full Disk Access, then refresh. If it still fails, quit and reopen Murten Utilities.")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    Text("The grant applies to all of Murten Utilities. App Permission Checkup opens the databases read-only; it changes a permission only through tccutil, after you confirm a reset. A build without a stable signature loses the grant with each update.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Open Full Disk Access Settings") { store.openFullDiskAccessSettings() }
                }
            }
            if inventory.userDatabaseUnavailable {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Your own permissions are not readable on this version of macOS", systemImage: "person.crop.circle.badge.questionmark")
                        .font(.headline)
                    Text("Permissions you gave for your account alone, such as Camera, Microphone, Photos, Contacts and Files & Folders, are not listed here. Check them in System Settings.")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    Menu("Open in System Settings") {
                        ForEach(PrivacyService.userLevelSettingsLists, id: \.anchor) { list in
                            Button(list.title) { store.openSettings(anchor: list.anchor) }
                        }
                    }
                    .fixedSize()
                }
            }
            ForEach(inventory.sources.filter(Self.isFailure), id: \.database) { source in
                Label(source.summary, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(DoctorStyle.warning).textSelection(.enabled)
            }
        }
        .padding(.vertical, 6)
    }

    private static func isFailure(_ source: DatabaseSource) -> Bool {
        if case .failed = source.reading { return true }
        return false
    }
}

// MARK: - Rows

private struct ClientGroupHeader: View {
    let group: PermissionInventory.ClientGroup
    let busy: Bool
    let reset: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: clientIcon(group.client))
                .resizable().interpolation(.high).frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.client.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(location).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            if !group.resettableEntries.isEmpty {
                Button("Reset…", action: reset).disabled(busy)
                    .help("Choose which of this app's permissions to reset")
            }
        }
        .padding(.vertical, 4)
    }

    private var location: String {
        let identifier = group.kind == .path ? "Recorded by path" : group.identifier
        switch group.client.presence {
        case .installed(let path): return group.kind == .path ? group.identifier : "\(identifier) · \(path)"
        case .inTrash(let path): return "\(identifier) · in the Trash: \(path)"
        case .offline(let path): return "\(identifier) · on a disk that is not connected: \(path)"
        case .missing: return group.kind == .path ? group.identifier : "\(identifier) · not on this Mac"
        }
    }
}

private struct InventoryEntryRow: View {
    @EnvironmentObject private var inventory: InventoryStore
    let entry: InventoryEntry
    let busy: Bool
    let reset: () -> Void
    @State private var showsDetails = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: serviceSymbol(entry.service))
                .foregroundStyle(entry.flags.contains(.highRisk) ? DoctorStyle.warning : DoctorStyle.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.service.title).font(.body.weight(.medium))
                    if let target = entry.record.target {
                        Text("controls \(entry.target?.name ?? target)").foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    Text(entry.record.database.title)
                    if let changed = entry.record.lastModified {
                        Text("·")
                        Text("Changed \(changed.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                if !entry.flagTitles.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(zip(entry.flagTitles.indices, entry.flagTitles)), id: \.0) { _, title in
                            StatusPill(title: title, color: flagColor(title))
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            StatusPill(title: entry.record.decision.title, color: decisionColor(entry.record.decision))
            Button { showsDetails.toggle() } label: { Image(systemName: "info.circle") }
                .buttonStyle(.plain)
                .accessibilityLabel("Details")
                .popover(isPresented: $showsDetails, arrowEdge: .trailing) { EntryDetails(entry: entry) }
            if entry.canReset {
                Button("Reset…", action: reset).disabled(busy)
            } else {
                Button("Settings") { inventory.openSettings(entry.service) }
                    .help(InventoryGuidance.steps(for: entry))
            }
        }
        .padding(.vertical, 3)
    }

    private func flagColor(_ title: String) -> Color {
        ["Leftover", "Look-alike", "Broken", "High-risk", "Target gone"].contains(title) ? DoctorStyle.warning : .secondary
    }
}

/// What the entry's record and flags mean, and what can be done about it.
private struct EntryDetails: View {
    let entry: InventoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(entry.service.title): \(entry.client.name)").font(.headline)
            detail("Identifier", entry.record.client)
            detail("Service", entry.service.identifier)
            if let target = entry.record.target { detail("Controls", target) }
            detail("Database", entry.record.database.title)
            if let reason = entry.record.reasonTitle { detail("Recorded reason", reason) }
            detail("Code requirement", signatureText)
            ForEach(flags, id: \.rawValue) { flag in
                Text(InventoryEntry.explanation(of: flag)).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            if !entry.canReset {
                Divider()
                Text(InventoryGuidance.steps(for: entry)).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            Text("A recorded decision is not proof that the app works. Organization policy can still allow or deny access.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .textSelection(.enabled)
        .padding(16)
        .frame(width: 380, alignment: .leading)
    }

    private var flags: [InventoryEntry.Flags] {
        [.leftover, .lookAlike, .broken, .highRisk, .offline, .missingTarget, .managed, .system].filter { entry.flags.contains($0) }
    }

    private var signatureText: String {
        switch entry.signature {
        case .matches: return "The app still matches the requirement recorded with this decision."
        case .changed: return "The app no longer matches the requirement recorded with this decision."
        case .notChecked(let reason): return "Not checked. \(reason)"
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(value).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Shared helpers

func decisionColor(_ decision: PermissionRecord.Decision) -> Color {
    switch decision {
    case .allowed: return DoctorStyle.accent
    case .limited: return DoctorStyle.warning
    case .denied, .unknown, .other: return .secondary
    }
}

@MainActor func clientIcon(_ client: ClientStatus) -> NSImage {
    if let path = client.presence.path, FileManager.default.fileExists(atPath: path) {
        return NSWorkspace.shared.icon(forFile: path)
    }
    return NSWorkspace.shared.icon(for: .applicationBundle)
}

func serviceSymbol(_ service: PrivacyService) -> String {
    switch service.resetName {
    case "SystemPolicyAllFiles": return "internaldrive"
    case "Accessibility": return "hand.point.up.left"
    case "PostEvent": return "keyboard"
    case "ListenEvent": return "waveform"
    case "ScreenCapture", "RemoteDesktop": return "rectangle.dashed.badge.record"
    case "AudioCapture": return "speaker.wave.2"
    case "Camera": return "camera"
    case "Microphone": return "mic"
    case "Photos", "PhotosAdd": return "photo"
    case "AddressBook", "ContactsFull", "ContactsLimited": return "person.crop.circle"
    case "Calendar": return "calendar"
    case "Reminders": return "checklist"
    case "AppleEvents": return "gearshape.2"
    case "SystemPolicyDesktopFolder", "SystemPolicyDocumentsFolder", "SystemPolicyDownloadsFolder", "FileProviderDomain", "FileProviderPresence":
        return "folder"
    case "SystemPolicyNetworkVolumes", "SystemPolicyRemovableVolumes": return "externaldrive"
    case "SystemPolicyAppBundles", "SystemPolicyAppData": return "app.badge"
    case "DeveloperTool", "SystemPolicyDeveloperFiles": return "hammer"
    case "BluetoothAlways": return "antenna.radiowaves.left.and.right"
    case "MediaLibrary": return "music.note"
    case "SpeechRecognition": return "waveform.and.mic"
    case "Motion": return "figure.walk"
    case "Willow": return "house"
    case "FocusStatus": return "moon"
    case "WebBrowserPublicKeyCredential": return "key"
    case "Location": return "location"
    default: return "lock.shield"
    }
}
