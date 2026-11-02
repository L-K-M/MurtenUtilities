import AppKit
import SwiftUI
import HallPassCore
import MurtenModuleKit

enum AppleDocumentation {
    /// Apple TN3179, Understanding local network privacy.
    static let localNetworkPrivacy = URL(string: "https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy")!
}

enum Palette {
    // Light appearance only (docs/ui-direction.md): the source's dark
    // variant is gone.
    static let green = Color(nsColor: NSColor(calibratedRed: 0.13, green: 0.43, blue: 0.35, alpha: 1))
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let background = Color(nsColor: .windowBackgroundColor)
}

struct InfoButton: View {
    let title: String
    let documentation: String
    var appleLink = false
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            Image(systemName: "info.circle").font(.system(size: 14)).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel("Information: \(title)")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(documentation).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                if appleLink {
                    Link("Apple Documentation ↗", destination: AppleDocumentation.localNetworkPrivacy)
                        .font(.system(size: 11))
                }
            }
            .padding(18).frame(width: 295).tint(Palette.green)
        }
    }
}

struct TicketMark: View {
    var size: CGFloat = 36
    var body: some View {
        // The standalone app showed its .icns from Bundle.main, which is the
        // suite's bundle now; the symbol was already its fallback.
        Image(systemName: "ticket.fill").font(.system(size: size * 0.7)).foregroundStyle(Palette.green)
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct ContentView: View {
    @Bindable var model: HallPassModel
    @State private var showingAdd = false
    @State private var showingReview = false
    @State private var confirmingReset = false
    @State private var confirmingReload = false
    @State private var confirmingImport = false
    @State private var confirmingLeaveDemo = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                header
                if model.isLoaded { editor } else { welcome }
                footer
            }
            .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.background).tint(Palette.green)
        .task { model.restoreRestartState() }
        .moduleCommands([
            ModuleCommand("Open Apple Documentation", id: "hallpass.tn3179") {
                _ = NSWorkspace.shared.open(AppleDocumentation.localNetworkPrivacy)
            }
        ])
        .sheet(isPresented: $showingAdd) { AddNetworkView(model: model) }
        .sheet(isPresented: $showingReview) { ReviewView(model: model) }
        .alert("HallPass", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .confirmationDialog("Remove All Exemptions?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Mark for Removal", role: .destructive) { model.resetDraft() }
        } message: { Text("The change is saved only when you apply it.") }
        .confirmationDialog("Discard the Draft and Reload?", isPresented: $confirmingReload, titleVisibility: .visible) {
            Button("Discard and Reload", role: .destructive) { Task { await model.load() } }
        }
        .confirmationDialog("Replace the Draft with a Backup?", isPresented: $confirmingImport, titleVisibility: .visible) {
            Button("Choose Backup…") { model.importBackup() }
        }
        .confirmationDialog("End the Preview and Discard the Draft?", isPresented: $confirmingLeaveDemo, titleVisibility: .visible) {
            Button("End Preview", role: .destructive) { model.leaveDemo() }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                TicketMark(size: 32)
                Text("HallPass").font(.system(size: 20, weight: .semibold, design: .rounded)).tracking(-0.6)
            }.padding(.top, 22).padding(.bottom, 32)
            ForEach(NetworkInterface.allCases) { interface in
                Button { model.selectedInterface = interface } label: {
                    HStack(spacing: 10) {
                        Image(systemName: interface.symbol).font(.system(size: 15)).frame(width: 19)
                        Text(interface.title).font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(model.isLoaded ? "\((model.draft[interface] ?? []).count)" : "–")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 11).padding(.vertical, 11)
                    .background(model.selectedInterface == interface ? Palette.green.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.bottom, 5)
                .accessibilityLabel("\(interface.title), \((model.draft[interface] ?? []).count) exemptions")
            }
            Spacer()
            Menu {
                Button("Export Saved State…", action: model.exportBackup)
                Button("Import Backup…") {
                    if model.isDirty { confirmingImport = true } else { model.importBackup() }
                }
                Divider()
                Button("Open Backups Folder", action: model.showBackups).disabled(model.isDemo)
                Divider()
                Button("Remove All Exemptions…", role: .destructive) { confirmingReset = true }
            } label: { Label("Backups", systemImage: "clock.arrow.circlepath").font(.system(size: 11)) }
                .menuStyle(.borderlessButton).disabled(!model.isLoaded || model.busy)
        }
        .padding(.horizontal, 16).padding(.bottom, 24)
        .frame(width: 180).frame(maxHeight: .infinity)
        .background(Palette.green.opacity(0.025))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Network Exemptions").font(.system(size: 23, weight: .semibold)).tracking(-0.6)
            InfoButton(title: "Network Exemptions", documentation: "Every app on this Mac can reach the IP ranges listed here, regardless of its local network permission. The exemptions apply in every network that uses these addresses. Wi-Fi and Ethernet are managed separately.", appleLink: true)
            Spacer(minLength: 6)
            if model.isDemo {
                HStack(spacing: 6) {
                    Text("Preview").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.green)
                    InfoButton(title: "Preview", documentation: "You are working with sample values. Changes stay in memory; the system settings are neither read nor changed.")
                    Button {
                        if model.isDirty { confirmingLeaveDemo = true } else { model.leaveDemo() }
                    } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
                    .buttonStyle(.plain).help("End Preview").accessibilityLabel("End Preview")
                }
            } else if model.needsRestart {
                HStack(spacing: 6) {
                    Label("Restart required", systemImage: "arrow.clockwise").font(.system(size: 10)).foregroundStyle(.orange)
                    InfoButton(title: "Restart Required", documentation: "The changes are saved. macOS applies them only after a restart. HallPass does not restart your Mac automatically.")
                }
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.rectangle.on.rectangle").font(.system(size: 32, weight: .light)).foregroundStyle(Palette.green)
            HStack(spacing: 9) {
                Button { Task { await model.load() } } label: {
                    Text(model.busy ? "Loading…" : "Load Configuration").padding(.horizontal, 7).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent).disabled(model.busy).keyboardShortcut("l", modifiers: .command)
                InfoButton(title: "Load Configuration", documentation: "macOS asks for administrator access so HallPass can read the system-wide settings. Loading changes nothing. The displayed exemptions are saved only after Review Changes and Apply.")
            }
            Button("Preview") { model.startDemo() }.buttonStyle(.link).font(.system(size: 11)).disabled(model.busy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.06)))
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("IP Ranges").font(.system(size: 12, weight: .semibold))
                Text("\(model.networks.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Button { showingAdd = true } label: { Label("Add", systemImage: "plus").font(.system(size: 11, weight: .medium)) }
                    .buttonStyle(.bordered).disabled(model.busy).keyboardShortcut("n", modifiers: .command)
            }.padding(16)
            Divider()
            if model.networks.isEmpty {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Text("No Exemptions").font(.system(size: 13)).foregroundStyle(.secondary)
                        InfoButton(title: "No Exemptions", documentation: "No exemptions are configured for this connection. Apps need their regular permission for local network access.")
                    }
                    Button("Add") { showingAdd = true }.buttonStyle(.link).font(.system(size: 11))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.networks.enumerated()), id: \.offset) { index, network in
                            networkRow(network)
                            if index < model.networks.count - 1 { Divider().padding(.leading, 16) }
                        }
                    }
                }.frame(maxHeight: .infinity)
            }
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.07)))
        .disabled(model.busy)
    }

    private func networkRow(_ network: String) -> some View {
        let cidr = try? CIDR(network)
        let isNew = !(model.snapshot?.configuration[model.selectedInterface] ?? []).contains(network)
        return HStack(spacing: 12) {
            Text(network).font(.system(size: 13, weight: .medium, design: .monospaced)).textSelection(.enabled)
            Spacer()
            if cidr == nil {
                InfoButton(title: "Invalid Existing Value", documentation: "This existing value is not valid CIDR notation. Remove it before saving or replace it with a valid IP range.")
            } else {
                Text(cidr!.isIPv6 ? "IPv6" : "IPv4").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            if isNew { Circle().fill(Palette.green).frame(width: 5, height: 5).help("New in the draft") }
            Button { model.remove(network) } label: {
                Image(systemName: "minus.circle").font(.system(size: 14)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).help("Remove").accessibilityLabel("Remove \(network)")
        }.padding(.horizontal, 16).padding(.vertical, 17)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if model.busy { ProgressView().controlSize(.small) }
            Button {
                if model.isDirty { confirmingReload = true } else { Task { await model.load() } }
            } label: { Image(systemName: "arrow.clockwise") }
            .help("Reload").accessibilityLabel("Reload").disabled(model.busy || !model.isLoaded)
            if model.isDirty {
                Button("Discard", action: model.discard).buttonStyle(.plain).font(.system(size: 11)).disabled(model.busy)
            }
            Spacer()
            if let message = model.validationMessage, model.isLoaded {
                InfoButton(title: "Check the Draft", documentation: message)
            } else if model.isDirty {
                Text("Unsaved").font(.system(size: 10)).foregroundStyle(.secondary)
            } else if let notice = model.notice {
                Text(notice).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Button { showingReview = true } label: {
                Text("Review Changes").font(.system(size: 12, weight: .medium)).padding(.horizontal, 5).padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent).disabled(!model.isDirty || model.busy || model.validationMessage != nil)
            .keyboardShortcut("s", modifiers: .command)
        }
    }
}

struct AddNetworkView: View {
    @Bindable var model: HallPassModel
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var both = true
    @State private var failure: String?
    @FocusState private var focused: Bool
    private var parsed: CIDR? { try? CIDR(input) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Add Network Range").font(.system(size: 19, weight: .semibold)).tracking(-0.5)
                Spacer()
                InfoButton(title: "Add Network Range", documentation: "The exemption applies to all apps. Entries are added to the draft first. Only Apply saves them in macOS.")
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Text("IP Range").font(.system(size: 12, weight: .medium))
                    InfoButton(title: "CIDR Notation", documentation: "Enter an IPv4 or IPv6 address with a network prefix, for example 192.168.1.0/24 or fd12:3456::/48. For a single address use /32 for IPv4 and /128 for IPv6. Host bits are normalized to the network address automatically.")
                }
                TextField("192.168.1.0/24", text: $input).textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, design: .monospaced)).controlSize(.large).focused($focused).onSubmit(add)
                if let parsed, parsed.notation != input.trimmingCharacters(in: .whitespacesAndNewlines) {
                    HStack(spacing: 7) {
                        Text("→ \(parsed.notation)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.green)
                        InfoButton(title: "Network Address", documentation: "The address was normalized to the start of the given network. This entire IP range is saved.")
                    }
                } else if !input.isEmpty && parsed == nil {
                    HStack(spacing: 7) {
                        Text("Invalid IP range").font(.system(size: 11)).foregroundStyle(.orange)
                        InfoButton(title: "Correct the IP Range", documentation: "A numeric IP address and a prefix are required: IPv4 /0 to /32, IPv6 /0 to /128. Hostnames, zone IDs and spaces inside the address are not allowed.")
                    }
                }
            }
            HStack(spacing: 7) {
                preset("Link-Local", "169.254.0.0/16")
                preset("Private /24", "192.168.1.0/24")
                preset("IPv6 Link-Local", "fe80::/10")
                InfoButton(title: "Presets", documentation: "Link-Local: 169.254.0.0/16. Private /24: 192.168.1.0/24 as an example; adjust it to your network. IPv6 Link-Local: fe80::/10. A click only fills in the input field.")
            }
            Toggle("Wi-Fi and Ethernet", isOn: $both).font(.system(size: 12))
            if !both { Text("Only \(model.selectedInterface.title)").font(.system(size: 11)).foregroundStyle(.secondary) }
            if parsed?.prefixLength == 0 {
                HStack(spacing: 7) {
                    Label("All IPv\(parsed!.isIPv6 ? "6" : "4") addresses", systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(.orange)
                    InfoButton(title: "Exemption for /0", documentation: "This range covers every address of the chosen IP version. Local network checks no longer apply to this entire address space.")
                }
            }
            if let failure { Text(failure).font(.system(size: 11)).foregroundStyle(.orange) }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add", action: add).buttonStyle(.borderedProminent).disabled(parsed == nil).keyboardShortcut(.defaultAction)
            }
        }.padding(25).frame(width: 455).tint(Palette.green).onAppear { focused = true }
    }

    private func preset(_ title: String, _ value: String) -> some View {
        Button(title) { input = value }.font(.system(size: 10)).buttonStyle(.bordered)
    }
    private func add() {
        guard parsed != nil else { return }
        do {
            try model.add(input, interfaces: both ? NetworkInterface.allCases : [model.selectedInterface])
            dismiss()
        } catch { failure = error.localizedDescription }
    }
}

struct ReviewView: View {
    @Bindable var model: HallPassModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Apply Changes?").font(.system(size: 20, weight: .semibold)).tracking(-0.5)
                Spacer()
                InfoButton(title: "Apply Changes", documentation: model.isDemo ? "Preview: the system settings are not changed." : "The exemptions apply to all apps. HallPass creates a backup before saving, and macOS asks for administrator access. The changes take effect after a restart.")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(NetworkInterface.allCases) { interface in
                        let before = model.snapshot?.configuration[interface] ?? []
                        let after = model.draft[interface] ?? []
                        let added = after.filter { !before.contains($0) }
                        let removed = before.filter { !after.contains($0) }
                        if model.snapshot?.configuration[interface] != model.draft[interface] {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(interface.title, systemImage: interface.symbol).font(.system(size: 12, weight: .semibold))
                                ForEach(added, id: \.self) { row($0, added: true) }
                                ForEach(removed, id: \.self) { row($0, added: false) }
                                if added.isEmpty && removed.isEmpty {
                                    Label("Reset the empty setting", systemImage: "minus.circle").font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }.frame(maxHeight: 260)
            Divider()
            HStack {
                Button("Back") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(model.isDemo ? "Apply Preview" : "Apply") {
                    dismiss()
                    Task { await model.save() }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(25).frame(width: 455).tint(Palette.green)
    }

    private func row(_ network: String, added: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: added ? "plus.circle.fill" : "minus.circle.fill").foregroundStyle(added ? Palette.green : Color.orange)
            Text(network).font(.system(size: 12, design: .monospaced))
            Spacer()
        }.accessibilityLabel("\(added ? "Add" : "Remove"): \(network)")
    }
}
