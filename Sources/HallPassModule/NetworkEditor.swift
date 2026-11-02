import SwiftUI
import HallPassCore

struct NetworkEditor: View {
    private enum Scope: String, CaseIterable {
        case selected, both
    }

    let model: HallPassModel
    let interface: NetworkInterface
    private let entry: NetworkRow?
    @Environment(\.dismiss) private var dismiss
    @State private var input: String
    @State private var scope = Scope.both
    @State private var failure: String?
    @FocusState private var focused: Bool

    init(model: HallPassModel, interface: NetworkInterface, entry: NetworkRow? = nil) {
        self.model = model
        self.interface = interface
        self.entry = entry
        _input = State(initialValue: entry?.notation ?? "")
    }

    private var parsed: CIDR? { try? CIDR(input) }
    private var title: String { entry == nil ? "Add Network Range" : "Edit Network Range" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.title2.bold())
                Text("The exemption applies to all apps on this Mac. Changes stay in the draft until you apply them.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)

            Form {
                Section {
                    TextField("IP Range", text: $input, prompt: Text("192.168.1.0/24"))
                        .monospaced().textFieldStyle(.roundedBorder)
                        .focused($focused).onSubmit(save)
                        .accessibilityHint("IPv4 or IPv6 address with a network prefix, for example 192.168.1.0/24")

                    if let parsed {
                        if parsed.notation != input.trimmingCharacters(in: .whitespacesAndNewlines) {
                            LabeledContent("Network Address") {
                                Text(parsed.notation).monospaced().textSelection(.enabled)
                            }
                        }
                        if parsed.prefixLength == 0 {
                            Label("This range covers every IPv\(parsed.isIPv6 ? "6" : "4") address.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text("Address")
                } footer: {
                    Text("CIDR notation: IPv4 /0 to /32, IPv6 /0 to /128. For a single address use /32 or /128. Host bits are normalized to the network address.")
                }

                Section("Connection") {
                    if entry == nil {
                        Picker("Add To", selection: $scope) {
                            Text(interface.title).tag(Scope.selected)
                            Text("Wi-Fi and Ethernet").tag(Scope.both)
                        }
                    } else {
                        LabeledContent("Edit In", value: interface.title)
                    }
                }

                Section("Presets") {
                    HStack {
                        preset("Link-Local", value: "169.254.0.0/16")
                        preset("Private /24", value: "192.168.1.0/24")
                        preset("IPv6 Link-Local", value: "fe80::/10")
                    }
                    Text("Presets only fill in the field. Adjust the range to your network.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red).padding(.horizontal, 24).padding(.bottom, 16)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(entry == nil ? "Add" : "Change", action: save)
                    .keyboardShortcut(.defaultAction).disabled(parsed == nil || !model.canEdit)
            }
            .padding(20)
        }
        .frame(width: 520, height: 540)
        .onAppear { focused = true }
        .onChange(of: input) { failure = nil }
    }

    private func preset(_ title: String, value: String) -> some View {
        Button(title) {
            input = value
            focused = true
        }
        .help(value)
    }

    private func save() {
        guard parsed != nil, model.canEdit else { return }
        do {
            if let entry {
                try model.edit(entry.id, notation: input, interface: interface)
            } else {
                try model.add(input, interfaces: scope == .both ? NetworkInterface.allCases : [interface])
            }
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}
