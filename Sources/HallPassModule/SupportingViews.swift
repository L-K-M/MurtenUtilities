import SwiftUI
import HallPassCore

enum HallPassHelp {
    static let appleDocumentation = URL(string: "https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy")!
    static let scope = "The exemptions apply to all apps on this Mac, in every network that uses these IP addresses. Wi-Fi and Ethernet are managed separately."
}

struct NetworkInspector: View {
    static let minimumWidth: CGFloat = 240
    static let idealWidth: CGFloat = 270
    static let maximumWidth: CGFloat = 360

    let rows: [NetworkRow]
    let interface: NetworkInterface
    let canEdit: Bool
    let edit: () -> Void

    var body: some View {
        Group {
            if rows.isEmpty {
                ContentUnavailableView("No IP Range Selected", systemImage: "info.circle", description: Text("Select an entry to check its address and scope."))
            } else {
                Form {
                    Section(rows.count == 1 ? "IP Range" : "\(rows.count) IP Ranges") {
                        if let row = rows.first, rows.count == 1 {
                            Text(row.notation).monospaced().textSelection(.enabled)
                            LabeledContent("Connection", value: interface.title)
                            if let cidr = row.cidr {
                                LabeledContent("Version", value: row.version)
                                LabeledContent("Prefix", value: "/\(cidr.prefixLength)")
                                if cidr.notation != row.notation {
                                    LabeledContent("Network Address") { Text(cidr.notation).monospaced().textSelection(.enabled) }
                                }
                            }
                            Label(row.status.rawValue, systemImage: row.status.symbol)
                                .foregroundStyle(row.status == .invalid ? Color.orange : Color.secondary)
                            Button("Edit IP Range…", action: edit).disabled(!canEdit)
                        } else {
                            LabeledContent("Connection", value: interface.title)
                            Text("Copy or remove the selection from the Edit menu or the shortcut menu.")
                        }
                    }

                    Section("Scope") {
                        Text(HallPassHelp.scope)
                        Text("The exemptions bypass local network permission checks. They are not firewall rules or permissions for individual apps.")
                            .foregroundStyle(.secondary)
                        if rows.contains(where: { $0.cidr?.prefixLength == 0 }) {
                            Label("A /0 prefix covers every address of its IP version.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }

                    if rows.contains(where: { $0.status == .invalid }) {
                        Section("Invalid Existing Value") {
                            Text("HallPass keeps existing values unchanged. Correct or remove invalid entries before applying.")
                        }
                    }

                    Section("Applying") {
                        Text("Changes take effect only after review, administrator confirmation and a restart.")
                        Link("Apple Documentation", destination: HallPassHelp.appleDocumentation)
                    }
                }
                .formStyle(.grouped)
            }
        }
        .frame(minWidth: Self.minimumWidth, idealWidth: Self.idealWidth, maxWidth: Self.maximumWidth)
        .accessibilityLabel("Information About the Selection")
    }
}

struct ReviewView: View {
    let model: HallPassModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Review Changes").font(.title2.bold())
                Text(model.isDemo ? "Preview: no system settings are changed." : HallPassHelp.scope)
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)

            List {
                ForEach(model.changes) { change in
                    Section {
                        ForEach(entries(for: change)) { entry in
                            changeRow(entry.network, kind: entry.kind)
                        }
                        if change.added.isEmpty, change.removed.isEmpty {
                            Text(structuralChange(change.interface)).foregroundStyle(.secondary)
                        }
                    } header: {
                        Label(change.interface.title, systemImage: change.interface.symbol)
                    }
                }
            }
            .textSelection(.enabled)

            if !model.isDemo {
                Label("A backup is made before saving. macOS asks for administrator access. A restart is required.", systemImage: "externaldrive.badge.timemachine")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(20)
            }

            Divider()
            HStack {
                Button("Keep Editing") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(model.isDemo ? "Apply Preview" : "Apply") {
                    dismiss()
                    Task { await model.save() }
                }
                .keyboardShortcut(.defaultAction).disabled(!model.canReview)
            }
            .padding(20)
        }
        .frame(width: 560, height: 500)
    }

    private enum ChangeKind: String {
        case addition, removal
        var title: String { self == .addition ? "Add" : "Remove" }
        var symbol: String { self == .addition ? "plus.circle" : "minus.circle" }
    }

    private struct ReviewEntry: Identifiable {
        let id: String
        let network: String
        let kind: ChangeKind
    }

    private func entries(for change: InterfaceChange) -> [ReviewEntry] {
        // List flattens row identities across additions, removals, and interfaces.
        [(ChangeKind.addition, change.added), (.removal, change.removed)].flatMap { kind, networks in
            networks.enumerated().map { index, network in
                ReviewEntry(id: "\(change.interface.rawValue)/\(kind.rawValue)/\(index)", network: network, kind: kind)
            }
        }
    }

    private func changeRow(_ network: String, kind: ChangeKind) -> some View {
        HStack(spacing: 10) {
            Image(systemName: kind.symbol).foregroundStyle(kind == .addition ? Color.accentColor : Color.orange)
                .accessibilityHidden(true)
            Text(network).monospaced()
            Spacer()
            Text(kind.title).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func structuralChange(_ interface: NetworkInterface) -> String {
        if model.draft[interface] == nil { return "Remove the empty setting" }
        if model.snapshot?.configuration[interface] == nil { return "Create an empty setting" }
        return "Update the order"
    }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("HallPass Help").font(.title2.bold()).padding(24)
            Form {
                Section("Local Network Exemptions") {
                    Text(HallPassHelp.scope)
                    Text("HallPass manages neither Wi-Fi network names nor firewall rules or permissions of individual apps. It installs no background service and needs no network connection.")
                }
                Section("Changing the Configuration") {
                    Text("1. Load the configuration (⌘L) and confirm as an administrator.")
                    Text("2. Choose Wi-Fi or Ethernet (⌘1 / ⌘2). Add an IP range with ⌘N; edit an entry by double-clicking it or pressing Return.")
                    Text("3. Review the changes (⌘S), then choose Apply. Restart the Mac only after that.")
                    Text("⌘-click or ⇧-click selects several entries to copy or remove together. ⌘Z undoes draft changes.")
                }
                Section("IP Ranges") {
                    Text("Examples: 169.254.0.0/16, 192.168.1.0/24, fe80::/10. Single addresses use /32 for IPv4 and /128 for IPv6. /0 covers every address of an IP version.")
                    Text("Each connection allows up to \(NetworkConfiguration.maximumNetworksPerInterface) entries. Existing values are not normalized when loading or exporting.")
                }
                Section("Backups and Recovery") {
                    Text("The Tool menu holds import, export and the backups folder. Export writes the most recently loaded or saved state. An import replaces only the draft and can be undone.")
                    Text("Before each apply, a backup is saved in “~/Library/Application Support/HallPass/Backups/”. Changes you have not applied are kept as a draft and restored the next time Murten Utilities opens. Before writing, HallPass checks the original system state again.")
                    Text("“Remove All Exemptions” empties both connections in the draft. After applying and restarting, the regular network permissions apply again.")
                }
                Section("More Information") {
                    Link("Apple TN3179: Local Network Privacy", destination: HallPassHelp.appleDocumentation)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 580, height: 600)
        .onExitCommand { dismiss() }
    }
}
