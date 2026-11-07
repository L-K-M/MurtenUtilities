import SwiftUI

struct ResetAllContentView: View {
    @EnvironmentObject private var doctor: DoctorStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session: ResetAllSession
    @State private var forceTarget: ResetAllProcessRow?
    @State private var showsClients = false

    init(doctor: DoctorStore) {
        _session = StateObject(wrappedValue: ResetAllSession(doctor: doctor))
    }

    private var busy: Bool { session.isApplying || doctor.isChecking || doctor.isRepairing }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading
            if session.failure != nil || session.inventoryFailure != nil { failureBanner }
            summary
            processTable
            Divider()
            actions
        }
        .padding(22)
        // Only the table, client popover and error details scroll. The repair
        // controls remain reachable for both large inventories and failures.
        .frame(width: 860, height: 620)
        .interactiveDismissDisabled(session.isApplying || doctor.isRepairing)
        .tint(.teal)
        .task { await session.monitor() }
        .alert("Force quit this process?", isPresented: Binding(
            get: { forceTarget != nil }, set: { if !$0 { forceTarget = nil } }
        ), presenting: forceTarget) { row in
            Button("Force Quit", role: .destructive) {
                Task { await session.forceQuit(row.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { row in
            Text("\(row.process.name) (PID \(String(row.process.processIdentifier))) will stop immediately. Unsaved work may be lost. Background helpers may restart automatically.")
        }
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: session.completed ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.system(size: 29, weight: .light))
                .foregroundStyle(session.completed ? .teal : .orange)
            VStack(alignment: .leading, spacing: 5) {
                Text(session.completed ? "Reset completed" : "Reset all access decisions")
                    .font(.title2.weight(.semibold))
                Text(session.completed
                     ? "Approve access again in System Settings. Restart any apps you left running."
                     : "Clear every app’s Accessibility, event-generation, and input-monitoring decisions. Completed resets cannot be undone.")
                    .font(.callout)
            }
        }
    }

    private var failureBanner: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(session.inventoryFailure == nil ? session.failureTitle : "Process status could not be verified",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if let failure = session.failure { Text(failure) }
                    if let failure = session.inventoryFailure { Text(failure) }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .frame(maxHeight: 54)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var summary: some View {
        HStack {
            Text(processSummary).font(.headline)
            Text(session.hasInspected ? "\(session.clients.count) known clients" : "Scope not yet verified")
                .foregroundStyle(.secondary)
            Button("Review Clients…") { showsClients = true }
                .popover(isPresented: $showsClients) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(session.clients.sorted(), id: \.self) { client in
                                Text(client).textSelection(.enabled)
                            }
                        }
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    }
                    .frame(width: 440, height: 240)
                }
                .disabled(!session.hasInspected)
            Spacer()
            Button("Refresh") { Task { await session.refresh() } }
                .disabled(busy || session.isRefreshing || session.completed)
        }
        .font(.callout)
    }

    private var processTable: some View {
        Table(session.rows) {
            TableColumn("App or helper") { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.process.name).fontWeight(.medium)
                    Text(row.process.executablePath).font(.caption).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .help(row.process.executablePath)
            }
            .width(min: 220)
            TableColumn("PID") { row in
                Text(String(row.process.processIdentifier)).monospacedDigit()
            }
            .width(55)
            TableColumn("State") { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.state.rawValue)
                    if let detail = row.detail { Text(detail).font(.caption).foregroundStyle(.orange) }
                }
                .lineLimit(1)
                .help(row.detail ?? row.state.rawValue)
                .foregroundStyle(row.state == .exited ? Color.secondary : Color.primary)
            }
            .width(140)
            TableColumn("Actions") { row in
                HStack(spacing: 6) {
                    Button("Quit") { Task { await session.quit(row.id) } }
                        .disabled(!row.isRunning || !row.process.canRequestTermination)
                    Button("Force Quit…") { forceTarget = row }
                        .disabled(!row.isRunning || !row.process.canForceTerminate)
                        .help(row.process.canForceTerminate
                              ? "Review the data-loss warning before force quitting this process"
                              : "Protected or unverified processes cannot be force quit here")
                }
                .disabled(busy || session.completed || session.inventoryFailure != nil)
            }
            .width(150)
        }
        .frame(minHeight: 140)
        .overlay {
            if session.rows.isEmpty {
                Text(emptyTableMessage)
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !session.completed {
                Toggle("I understand the risks. Reset even if apps are still running.", isOn: $session.allowsRunningApps)
                    .toggleStyle(.checkbox)
                    .disabled(busy)
                Text(session.allowsRunningApps
                     ? "Apps will not be quit automatically. They may retain stale permissions or recreate records. Save your work and restart them afterward."
                     : "Normally, every affected process must stay closed. Force Quit is never automatic. Apps are not reopened afterward.")
                    .font(.caption)
                    .foregroundStyle(session.allowsRunningApps ? Color.orange : Color.secondary)
            }
            HStack {
                if session.isApplying || (!session.hasInspected && session.inventoryFailure == nil) {
                    ProgressView().controlSize(.small)
                }
                Text(session.activity).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                if session.completed {
                    Button("Open System Settings") { doctor.openSettings(.accessibility) }
                }
                Button(session.completed ? "Done" : "Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(session.isApplying || doctor.isRepairing)
                if !session.completed {
                    Button(resetTitle, role: .destructive) { Task { await session.reset() } }
                        .buttonStyle(.borderedProminent)
                        .tint(session.allowsRunningApps ? .orange : .teal)
                        .disabled(!session.canReset || busy)
                }
            }
        }
    }

    private var emptyTableMessage: String {
        if session.inventoryFailure != nil { return "Process status is unavailable. Refresh to try again." }
        return session.hasInspected ? "No affected processes are running." : "Reading affected apps and helpers…"
    }

    private var processSummary: String {
        guard session.hasInspected else {
            return session.inventoryFailure == nil ? "Reading process status…" : "Process status unavailable"
        }
        let exited = session.rows.filter { $0.state == .exited }.count
        if session.inventoryFailure != nil {
            return "\(session.unverifiedCount) unverified · \(exited) previously exited"
        }
        return "\(session.runningCount) running · \(exited) exited"
    }

    private var resetTitle: String {
        if session.allowsRunningApps { return "Reset Anyway" }
        return session.failure == nil ? "Quit Apps and Reset All" : "Retry Quit and Reset"
    }
}
