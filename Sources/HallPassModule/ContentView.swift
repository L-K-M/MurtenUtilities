import AppKit
import SwiftUI
import HallPassCore
import MurtenModuleKit

struct NetworkRow: Identifiable {
    enum Status: String {
        case saved = "Saved"
        case added = "Added"
        case invalid = "Invalid Value"

        var symbol: String {
            switch self {
            case .saved: "checkmark"
            case .added: "plus.circle"
            case .invalid: "exclamationmark.triangle"
            }
        }
    }

    let id: Int
    let notation: String
    let status: Status
    var cidr: CIDR? { try? CIDR(notation) }
    var version: String { cidr.map { $0.isIPv6 ? "IPv6" : "IPv4" } ?? "–" }
}

struct ContentView: View {
    private static let minimumDetailWidth: CGFloat = 430

    @Bindable var model: HallPassModel
    @Environment(\.undoManager) private var windowUndoManager
    // The suite's window is shared by every pane, so the keys carry the module id.
    @SceneStorage("hallpass.selectedInterface") private var interfaceName = NetworkInterface.wifi.rawValue
    @SceneStorage("hallpass.showsInspector") private var showsInspector = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var selection = Set<Int>()
    @State private var searchText = ""
    @State private var sheet: WorkspaceSheet?
    @State private var confirmation: DraftConfirmation?
    @State private var showingFilePanel = false
    @State private var window: NSWindow?
    @FocusState private var searchFocused: Bool

    private var interface: NetworkInterface { NetworkInterface(rawValue: interfaceName) ?? .wifi }
    private var available: Bool { !model.busy && sheet == nil && confirmation == nil && !showingFilePanel }

    private var rows: [NetworkRow] {
        var saved = (model.snapshot?.configuration[interface] ?? [])
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return (model.draft[interface] ?? []).enumerated().map { index, notation in
            let wasSaved = saved[notation, default: 0] > 0
            saved[notation, default: 0] -= 1
            let status: NetworkRow.Status = (try? CIDR(notation)) == nil ? .invalid : (wasSaved ? .saved : .added)
            return NetworkRow(id: index, notation: notation, status: status)
        }
    }

    private var visibleRows: [NetworkRow] {
        guard !searchText.isEmpty else { return rows }
        return rows.filter { $0.notation.localizedStandardContains(searchText) || $0.version.localizedStandardContains(searchText) }
    }

    private var selectedRows: [NetworkRow] { visibleRows.filter { selection.contains($0.id) } }

    private var windowContents: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 280)
        } detail: {
            detail
                .navigationSplitViewColumnWidth(min: Self.minimumDetailWidth, ideal: 520)
                .navigationTitle("Local Network Access")
                .navigationSubtitle(interface.title)
                .toolbar { toolbar }
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: $showsInspector) {
            NetworkInspector(rows: selectedRows, interface: interface, canEdit: model.canEdit && available) {
                perform(.edit)
            }
            .inspectorColumnWidth(min: NetworkInspector.minimumWidth, ideal: NetworkInspector.idealWidth, max: NetworkInspector.maximumWidth)
        }
        .moduleCommands(WorkspaceActions(
            model: model, available: available, selectionCount: selectedRows.count,
            selectionIsActive: !searchFocused, showsInspector: showsInspector, interface: interface, perform: perform
        ).moduleCommands)
    }

    var body: some View {
        windowContents
        .background(HostingWindowReader { window = $0 }.frame(width: 0, height: 0))
        .task { model.restoreSession() }
        .onChange(of: windowUndoManager, initial: true) { model.useUndoManager(windowUndoManager) }
        .onDisappear { model.releaseUndoManager() }
        .sheet(item: $sheet) { request in
            switch request {
            case .add:
                NetworkEditor(model: model, interface: interface)
            case .edit(let row):
                NetworkEditor(model: model, interface: interface, entry: row)
            case .review:
                ReviewView(model: model)
            case .help:
                HelpView()
            }
        }
        .alert("Could Not Finish", isPresented: Binding(
            get: { model.error != nil }, set: { if !$0 { model.error = nil } }
        )) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
        .alert(confirmation?.title ?? "", isPresented: Binding(
            get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }
        ), presenting: confirmation) { pending in
            Button(pending.actionTitle, role: .destructive) { confirm(pending) }
            Button("Cancel", role: .cancel) { }
        } message: { pending in
            Text(pending.message)
        }
        .onChange(of: model.draft) { selection.removeAll() }
        .onChange(of: interfaceName) { selection.removeAll() }
        .onChange(of: searchText) { selection.formIntersection(Set(visibleRows.map(\.id))) }
    }

    private var sidebar: some View {
        List(selection: Binding<NetworkInterface?>(
            get: { interface }, set: { if let value = $0 { interfaceName = value.rawValue } }
        )) {
            Section("Connections") {
                ForEach(NetworkInterface.allCases) { connection in
                    Label(connection.title, systemImage: connection.symbol)
                        .badge(model.isLoaded ? Text("\((model.draft[connection] ?? []).count)") : Text(""))
                        .tag(connection)
                }
            }
        }
        .listStyle(.sidebar)
        .disabled(!available)
        .accessibilityLabel("Network Connection")
    }

    private var detail: some View {
        VStack(spacing: 0) {
            notices
            Group {
                if model.isLoaded {
                    networkTable
                } else {
                    welcome
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            statusBar
        }
        // Bound wrapping before the split view measures its minimum size.
        .frame(minWidth: Self.minimumDetailWidth, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var networkTable: some View {
        Table(visibleRows, selection: $selection) {
            TableColumn("IP Range") { row in
                Text(row.notation).monospaced()
            }
            .width(min: 190, ideal: 250)
            TableColumn("Version", value: \.version).width(65)
            TableColumn("Status") { row in
                Label(row.status.rawValue, systemImage: row.status.symbol)
                    .foregroundStyle(row.status == .invalid ? Color.orange : Color.secondary)
                    .accessibilityLabel(row.status.rawValue)
            }
            .width(min: 110, ideal: 125)
        }
        .disabled(model.busy)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search IP Ranges")
        .searchFocused($searchFocused)
        .onDeleteCommand {
            guard model.canEdit, available, !searchFocused else { return }
            model.remove(selection, interface: interface)
        }
        .onCopyCommand(perform: selectedRows.isEmpty ? nil : {
            [NSItemProvider(object: selectedRows.map(\.notation).joined(separator: "\n") as NSString)]
        })
        .onKeyPress(.return) {
            guard available, model.canEdit, !searchFocused, selectedRows.count == 1 else { return .ignored }
            perform(.edit)
            return .handled
        }
        .contextMenu(forSelectionType: Int.self) { items in
            Button("Edit IP Range…") { edit(items) }
                .disabled(items.count != 1 || !model.canEdit)
            Button("Copy") { copy(items) }.disabled(items.isEmpty)
            Divider()
            Button("Remove", role: .destructive) { model.remove(items, interface: interface) }
                .disabled(items.isEmpty || !model.canEdit)
        } primaryAction: { items in
            edit(items)
        }
        .overlay {
            if visibleRows.isEmpty {
                ContentUnavailableView {
                    Label(searchText.isEmpty ? "No Exemptions" : "No Matches", systemImage: searchText.isEmpty ? interface.symbol : "magnifyingglass")
                } description: {
                    Text(searchText.isEmpty
                         ? "The regular local network permissions apply to \(interface.title)."
                         : "No IP range matches “\(searchText)”.")
                } actions: {
                    if searchText.isEmpty {
                        Button("Add Network Range…") { perform(.add) }.disabled(!model.canEdit)
                    } else {
                        Button("Clear Search") { searchText = "" }
                    }
                }
            }
        }
        .accessibilityLabel("IP Ranges for \(interface.title)")
    }

    private var welcome: some View {
        ContentUnavailableView {
            Label {
                Text("Local Network Exemptions")
            } icon: {
                // The standalone app showed its own icon here; the suite's
                // application icon is not HallPass's.
                Image(systemName: "ticket.fill")
                    .resizable().scaledToFit().frame(width: 72, height: 72).foregroundStyle(.secondary)
            }
        } description: {
            Text("Manage the IP ranges every app on this Mac may reach without a local network permission prompt. Loading needs administrator access.")
                .frame(maxWidth: 390)
        } actions: {
            Button("Load Configuration…") { perform(.load) }
                .buttonStyle(.borderedProminent).disabled(!available)
            Button("Try with Sample Data") { perform(.preview) }.disabled(!available)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Button(model.isLoaded ? "Reload Configuration" : "Load Configuration", systemImage: "arrow.clockwise") {
                perform(.load)
            }
            .help("Load the configuration (⌘L)")
            .disabled(!available)
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup {
            Button("Add Network Range", systemImage: "plus") { perform(.add) }
                .help("Add a network range (⌘N)").disabled(!available || !model.canEdit)
            Button("Remove Selection", systemImage: "minus") { model.remove(selection, interface: interface) }
                .help("Remove the selected IP ranges").disabled(!available || !model.canEdit || selectedRows.isEmpty)
        }
        ToolbarSpacer(.fixed)
        ToolbarItem(placement: .primaryAction) {
            Button("Review Changes…") { perform(.review) }
                .help("Review the changes before applying them (⌘S)")
                .disabled(!available || !model.canReview)
        }
        ToolbarItem {
            Button("Information", systemImage: "sidebar.right") { showsInspector.toggle() }
                .help("Show or hide information (⌥⌘I)")
                .disabled(!available || !model.isLoaded)
                .accessibilityValue(showsInspector ? "Shown" : "Hidden")
        }
    }

    private var notices: some View {
        VStack(spacing: 0) {
            if model.isDemo {
                banner("Preview", symbol: "eye", text: "Sample data. The system settings stay unchanged.") {
                    Button("End Preview") { perform(.preview) }.disabled(!available)
                }
            } else if model.recoveryBlocked {
                banner("Draft File Protected", symbol: "exclamationmark.triangle", text: "Check the permissions of the Local Network Access data folder (named “HallPass” on disk), then quit and reopen Murten Utilities before you make changes.") {
                    EmptyView()
                }
            } else if model.requiresReload {
                banner("Check the System State", symbol: "exclamationmark.triangle", text: "Reload the configuration. The draft and the automatic backup are kept until then.") {
                    Button("Reload…") { perform(.load) }.disabled(!available)
                }
            } else if model.recoveredDraft {
                banner("Draft Restored", symbol: "arrow.counterclockwise", text: "Not applied yet. Saving checks the system state again.") {
                    EmptyView()
                }
            }

            if model.needsRestart, !model.isDemo {
                banner("Restart Required", symbol: "restart", text: "The saved exemptions take effect only after a restart.") {
                    EmptyView()
                }
            }

            if model.isLoaded, model.validationMessage != nil {
                banner("Invalid IP Ranges", symbol: "exclamationmark.triangle", text: "Correct or remove the marked values before applying.") {
                    Button("Information") { showsInspector = true }
                }
            }
        }
    }

    private func banner<Actions: View>(_ title: String, symbol: String, text: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol).foregroundStyle(.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.callout.bold())
                    Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                actions().controlSize(.small)
            }
            .padding(12)
            Divider()
        }
        .background(.background)
    }

    private var statusBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                if model.busy {
                    ProgressView().controlSize(.small)
                    Text(model.activity == .loading ? "Loading the configuration…" : "Applying changes…")
                } else if let notice = model.notice {
                    Text(notice)
                } else if model.isLoaded {
                    Text(searchText.isEmpty ? Self.rangeCount(rows.count) : "\(visibleRows.count) of \(Self.rangeCount(rows.count))")
                    if !selection.isEmpty { Text("· \(selection.count) selected") }
                } else {
                    Text("No configuration loaded")
                }
                Spacer(minLength: 8)
                if model.isDirty { Label("Not applied", systemImage: "pencil") }
            }
            .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 10)
            .fixedSize(horizontal: false, vertical: true)
        }
        .background(.bar)
    }

    private static func rangeCount(_ count: Int) -> String {
        count == 1 ? "1 IP range" : "\(count) IP ranges"
    }

    private func perform(_ command: WorkspaceCommand) {
        guard available else { return }
        switch command {
        case .add:
            guard model.canEdit else { return }
            sheet = .add
        case .edit:
            edit(selection)
        case .remove:
            guard !searchFocused else { return }
            model.remove(selection, interface: interface)
        case .review:
            guard model.canReview else { return }
            sheet = .review
        case .load:
            if model.isDirty { confirmation = .reload } else { Task { await model.load() } }
        case .discard:
            confirmation = .discard
        case .reset:
            confirmation = .reset
        case .preview:
            guard model.isDemo else { model.startDemo(); return }
            if model.isDirty { confirmation = .leavePreview } else { model.leaveDemo() }
        case .importBackup:
            guard model.canEdit, let window else { return }
            showingFilePanel = true
            BackupPanels.open(in: window) { url in
                showingFilePanel = false
                if let url { model.importBackup(from: url) }
            }
        case .exportBackup:
            guard model.isLoaded, let window else { return }
            showingFilePanel = true
            BackupPanels.save(in: window) { url in
                showingFilePanel = false
                if let url { model.exportBackup(to: url) }
            }
        case .backups:
            model.showBackups()
        case .inspector:
            showsInspector.toggle()
        case .search:
            searchFocused = true
        case .wifi:
            interfaceName = NetworkInterface.wifi.rawValue
        case .ethernet:
            interfaceName = NetworkInterface.ethernet.rawValue
        case .help:
            sheet = .help
        }
    }

    private func edit(_ items: Set<Int>) {
        guard available, model.canEdit, items.count == 1,
              let row = rows.first(where: { items.contains($0.id) }) else { return }
        selection = items
        sheet = .edit(row)
    }

    private func copy(_ items: Set<Int>) {
        let text = rows.filter { items.contains($0.id) }.map(\.notation).joined(separator: "\n")
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func confirm(_ pending: DraftConfirmation) {
        confirmation = nil
        switch pending {
        case .reload: Task { await model.load() }
        case .discard: model.discard()
        case .reset: model.resetDraft()
        case .leavePreview: model.leaveDemo()
        }
    }
}

private enum WorkspaceSheet: Identifiable {
    case add, edit(NetworkRow), review, help

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let row): "edit-\(row.id)"
        case .review: "review"
        case .help: "help"
        }
    }
}

private enum DraftConfirmation {
    case reload, discard, reset, leavePreview

    var title: String {
        switch self {
        case .reload: "Discard the Draft and Reload?"
        case .discard: "Discard Changes?"
        case .reset: "Remove All Exemptions?"
        case .leavePreview: "End the Preview?"
        }
    }

    var message: String {
        switch self {
        case .reload: "The system state replaces the changes you have not applied."
        case .discard: "The draft returns to the most recently loaded or saved state. You can undo this."
        case .reset: "The Wi-Fi and Ethernet exemptions are removed from the draft. Only applying and a restart change the settings in effect."
        case .leavePreview: "Your changes to the sample data are discarded."
        }
    }

    var actionTitle: String {
        switch self {
        case .reload: "Discard and Reload"
        case .discard: "Discard Changes"
        case .reset: "Mark for Removal"
        case .leavePreview: "End Preview"
        }
    }
}
