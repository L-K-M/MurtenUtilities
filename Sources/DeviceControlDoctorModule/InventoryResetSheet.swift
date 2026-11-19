import SwiftUI
import DoctorCore

/// What a reset sheet offers: some apps' entries, grouped into the units
/// `tccutil` resets together (one app and one service), some preselected.
struct InventoryResetRequest: Identifiable {
    /// One app's entries of one service: what one command resets.
    struct Unit: Identifiable {
        let id: String
        let entries: [InventoryEntry]
        var first: InventoryEntry { entries[0] }
    }

    enum Kind { case app(String), cleanup }

    let id = UUID()
    let kind: Kind
    let units: [Unit]
    /// Entries `tccutil` cannot reset, with their System Settings steps.
    let settingsOnly: [InventoryEntry]
    let preselected: Set<String>

    init(client: String, entries: [InventoryEntry], preselected: Set<String>) {
        self.init(kind: .app(client), entries: entries, preselected: preselected)
    }

    /// Every leftover, all units preselected.
    init(cleanup leftovers: [InventoryEntry]) {
        self.init(kind: .cleanup, entries: leftovers, preselected: nil)
    }

    private init(kind: Kind, entries: [InventoryEntry], preselected: Set<String>?) {
        self.kind = kind
        var order: [String] = []
        var grouped: [String: [InventoryEntry]] = [:]
        var settingsOnly: [InventoryEntry] = []
        for entry in entries {
            guard entry.canReset else { settingsOnly.append(entry); continue }
            let id = Self.unitID(entry)
            if grouped[id] == nil { order.append(id) }
            grouped[id, default: []].append(entry)
        }
        units = order.compactMap { id in grouped[id].map { Unit(id: id, entries: $0) } }
        self.settingsOnly = settingsOnly
        self.preselected = preselected ?? Set(order)
    }

    static func unitID(_ entry: InventoryEntry) -> String {
        entry.record.client + "\u{1F}" + entry.service.identifier
    }

    var title: String {
        switch kind {
        case .app(let name): return "Reset permissions for “\(name)”"
        case .cleanup: return "Clean up leftovers"
        }
    }
}

/// The confirmation every inventory reset passes, then its verified result.
struct InventoryResetSheet: View {
    @EnvironmentObject private var inventory: InventoryStore
    @EnvironmentObject private var doctor: DoctorStore
    @Environment(\.dismiss) private var dismiss
    let request: InventoryResetRequest
    @State private var selected: Set<String>
    @State private var result: InventoryResetResult?
    @State private var isRunning = false
    @State private var busyMessage: String?

    init(request: InventoryResetRequest) {
        self.request = request
        _selected = State(initialValue: request.preselected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.title).font(.title2.weight(.semibold))
            if let result {
                resultView(result)
            } else {
                confirmation
            }
            HStack {
                if isRunning {
                    ProgressView().controlSize(.small)
                    Text("Resetting, then reading the databases again…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if result == nil {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(isRunning)
                    Button(resetTitle, role: .destructive) { run() }
                        .disabled(isRunning || chosenUnits.isEmpty || doctor.isRepairing || doctor.isChecking)
                } else {
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 600)
        .frame(minHeight: 340, maxHeight: 640)
        .interactiveDismissDisabled(isRunning)
    }

    private var chosenUnits: [InventoryResetRequest.Unit] { request.units.filter { selected.contains($0.id) } }

    private var resetTitle: String {
        if chosenUnits.isEmpty { return "Reset" }
        return chosenUnits.count == 1 ? "Reset 1 Permission" : "Reset \(chosenUnits.count) Permissions"
    }

    // MARK: - Confirmation

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(explanation).font(.callout).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(request.units) { unit in
                        Toggle(isOn: binding(unit.id)) { unitLabel(unit) }
                            .toggleStyle(.checkbox)
                    }
                    if !request.settingsOnly.isEmpty {
                        Divider()
                        Text("Only in System Settings").font(.headline)
                        ForEach(request.settingsOnly) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(entry.client.name): \(entry.service.title)").font(.callout.weight(.medium))
                                Text(InventoryGuidance.steps(for: entry)).font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120)
            if let busyMessage {
                Label(busyMessage, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(DoctorStyle.warning)
            }
        }
    }

    private var explanation: String {
        var text = "tccutil removes the selected decisions, including those of other installed copies of the app and, for Automation, every app it controls. This cannot be undone: macOS asks again the next time the app needs access. A running app may keep its current access until it quits, so save your work and quit it first. Organization (MDM) policy cannot be changed here."
        if case .cleanup = request.kind {
            text += " tccutil can reset only apps macOS can still find, such as one in the Trash. For the rest, the result shows the System Settings steps."
        }
        return text
    }

    private func unitLabel(_ unit: InventoryResetRequest.Unit) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if case .cleanup = request.kind {
                Text("\(unit.first.client.name): \(unit.first.service.title)").font(.callout.weight(.medium))
            } else {
                Text(unit.first.service.title).font(.callout.weight(.medium))
            }
            Text(unitDetail(unit)).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func unitDetail(_ unit: InventoryResetRequest.Unit) -> String {
        let records = unit.entries.map { entry -> String in
            var text = "\(entry.record.decision.title), \(entry.record.database.title.lowercased())"
            if let target = entry.record.target { text += ", controls \(entry.target?.name ?? target)" }
            return text
        }
        return "tccutil reset \(unit.first.service.resetName) \(unit.first.record.client) · " + records.joined(separator: "; ")
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(get: { selected.contains(id) }, set: { on in
            if on { selected.insert(id) } else { selected.remove(id) }
        })
    }

    private func run() {
        let entries = chosenUnits.flatMap(\.entries) + request.settingsOnly
        isRunning = true
        busyMessage = nil
        Task {
            if let outcome = await inventory.reset(entries) {
                result = outcome
            } else {
                busyMessage = ProcessTerminationError.busy.localizedDescription
            }
            isRunning = false
        }
    }

    // MARK: - Result

    private func resultView(_ result: InventoryResetResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(result.summary).font(.callout).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(result.items) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: item.outcome == .removed ? "checkmark.circle.fill" : "exclamationmark.circle")
                                .foregroundStyle(item.outcome == .removed ? DoctorStyle.accent : DoctorStyle.warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(item.entry.client.name): \(item.entry.service.title), \(item.entry.record.database.title.lowercased())")
                                    .font(.callout.weight(.medium))
                                Text(outcomeText(item)).font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                            Spacer(minLength: 6)
                            if item.outcome != .removed {
                                Button("Settings") { inventory.openSettings(item.entry.service) }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Removal is checked against a fresh read of the databases. Check System Settings and test the app; a removed decision is asked for again the next time it needs access.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func outcomeText(_ item: InventoryResetResult.Item) -> String {
        switch item.outcome {
        case .removed: return "Removed."
        case .stillRecorded: return "Still recorded after the reset. " + InventoryGuidance.steps(for: item.entry)
        case .failed(let detail): return "tccutil did not reset it: \(detail) " + InventoryGuidance.steps(for: item.entry)
        case .uncertain(let detail): return "\(detail) It is still recorded. " + InventoryGuidance.steps(for: item.entry)
        case .unverified: return "tccutil reported success, but the database could not be read again to check."
        case .skipped: return InventoryGuidance.steps(for: item.entry)
        }
    }
}
