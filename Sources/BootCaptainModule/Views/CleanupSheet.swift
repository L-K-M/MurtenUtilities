import SwiftUI
import BootCaptainCore

/// Review flow for broken startup leftovers. Nothing is preselected.
/// Already-cleaned items are excluded, so repeated runs never re-attempt them.
/// System items are listed but cannot be selected: they need the privileged
/// helper the suite leaves out (`HelperClient`), and with it the standalone
/// app's separate administrator confirmation.
struct CleanupSheet: View {
    let candidates: [CleanupPlanner.Candidate]
    @EnvironmentObject var scan: ScanViewModel
    @EnvironmentObject var cleanup: CleanupService
    @EnvironmentObject var helper: HelperClient
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var didInit = false

    /// Candidates that have not already been cleaned this session.
    private var pending: [CleanupPlanner.Candidate] {
        cleanup.pending(from: candidates)
    }
    private var userActionable: [CleanupPlanner.Candidate] {
        pending.filter { $0.eligibility == .userVaultMove || $0.eligibility == .loginItemRemoval }
    }
    private var systemActionable: [CleanupPlanner.Candidate] {
        pending.filter { $0.eligibility == .requiresHelper }
    }
    /// Selected IDs that are still pending (stale selections drop out).
    /// Only items this build can act on are selectable.
    private var effectiveSelection: [CleanupPlanner.Candidate] {
        userActionable.filter { selected.contains($0.itemID) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !userActionable.isEmpty { userSection }
                    if !systemActionable.isEmpty { systemSection }
                    if pending.isEmpty && !cleanup.performed.isEmpty { allDoneNote }
                    if !cleanup.performed.isEmpty { resultsSection }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 540)
        .interactiveDismissDisabled(cleanup.isWorking)
        .onAppear {
            guard !didInit else { return }
            didInit = true
            selected = []
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "bandage.fill")
                .font(.system(size: 26)).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Review Broken Startup Items").font(.title3.bold())
                Text("Review the evidence and choose each item you want BootCaptain to change.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var userSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current-user items").font(.headline)
            Text("LaunchAgent files move to a vault. Login item records are removed through System Events and restoration is best-effort. In-app undo history lasts only for this session.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(userActionable) { row($0) }
        }
    }

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("System items — needs administrator approval", systemImage: "lock.shield")
                .font(.headline)
            Text("These live in /Library and need BootCaptain's administrator helper. \(HelperClient.unavailableReason)")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(systemActionable) { row($0).disabled(!helper.isAvailable) }
        }
    }

    private func row(_ candidate: CleanupPlanner.Candidate) -> some View {
        Toggle(isOn: binding(for: candidate.itemID)) {
            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.displayName).fontWeight(.medium)
                Text(candidate.reason).font(.caption).foregroundStyle(.secondary)
                if let path = candidate.sourcePath {
                    Text(path).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
        }
        .toggleStyle(.checkbox)
    }

    private var allDoneNote: some View {
        Label("All broken items handled.", systemImage: "checkmark.seal.fill")
            .foregroundStyle(.green)
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Results").font(.headline)
            ForEach(cleanup.performed) { action in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: action.outcome.status == .committed
                          ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(action.outcome.status == .committed ? .green : .orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(action.candidate.displayName).fontWeight(.medium)
                        Text(action.outcome.message).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if action.inverse != nil && !action.undone {
                        Button("Undo") { Task { await cleanup.undo(action, helper: helper) } }
                            .controlSize(.small)
                            .disabled(cleanup.isWorking)
                    } else if action.undone {
                        Text("Undone").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if cleanup.isWorking { ProgressView().controlSize(.small) }
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(cleanup.isWorking)
            Button {
                performSelection()
            } label: {
                let n = effectiveSelection.count
                Text(n == 0 ? "Select Items" : "Apply to \(n) Item\(n == 1 ? "" : "s")")
            }
            .disabled(effectiveSelection.isEmpty || cleanup.isWorking)
        }
        .padding(16)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(id) },
            set: { on in if on { selected.insert(id) } else { selected.remove(id) } })
    }

    private func performSelection() {
        let selection = effectiveSelection
        Task {
            await cleanup.perform(selection, helper: helper)
            scan.scan(diagnose: false)
        }
    }
}
