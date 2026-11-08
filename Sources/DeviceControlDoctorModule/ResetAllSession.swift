import Combine
import DoctorCore
import Foundation

/// Sheet-local repair state. Closing and reopening the sheet always drops the
/// running-app acknowledgement; neither monitoring nor defaults can enable it.
@MainActor
final class ResetAllSession: ObservableObject {
    @Published private(set) var clients = Set<String>()
    @Published private(set) var rows: [ResetAllProcessRow] = []
    @Published private(set) var hasInspected = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isApplying = false
    @Published private(set) var completed = false
    @Published private(set) var failure: String?
    @Published private(set) var failureTitle = "Last reset attempt stopped"
    @Published private(set) var inventoryFailure: String?
    @Published private(set) var activity = "Reading affected apps and helpers…"
    @Published var allowsRunningApps = false

    private let doctor: DoctorStore

    init(doctor: DoctorStore) {
        self.doctor = doctor
    }

    var canReset: Bool {
        hasInspected && !clients.isEmpty && inventoryFailure == nil
            && !isRefreshing && !isApplying && !completed
            && !doctor.isChecking && !doctor.isRepairing
    }

    var runningCount: Int { rows.filter(\.isRunning).count }
    var unverifiedCount: Int { rows.filter { $0.state == .unverified }.count }

    func monitor() async {
        while !Task.isCancelled && !completed {
            if !isApplying && !doctor.isChecking && !doctor.isRepairing { await refresh() }
            do { try await Task.sleep(nanoseconds: 1_000_000_000) }
            catch { return }
        }
    }

    func refresh() async {
        guard !isRefreshing, !isApplying, !completed,
              !doctor.isChecking, !doctor.isRepairing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let preparation = try await doctor.inspectResetAll(including: clients)
            guard !Task.isCancelled else { return }
            clients.formUnion(preparation.clients)
            observe(preparation.runningProcesses)
            inventoryFailure = nil
            hasInspected = true
            activity = "\(runningCount) running · \(rows.count - runningCount) exited"
        } catch is CancellationError {
            return
        } catch {
            inventoryFailure = error.localizedDescription
            activity = "Live process status is unavailable. Refresh to try again."
            // A failed inventory cannot prove that any previously seen process
            // exited. Disable actions on stale rows until a complete refresh.
            for index in rows.indices where rows[index].state != .exited {
                rows[index].state = .unverified
            }
        }
    }

    func reset() async {
        guard canReset else { return }
        let policy: ResetAllPermissions.RunningAppsPolicy = allowsRunningApps ? .allowRunning : .requireClosed
        isApplying = true
        failure = nil
        failureTitle = "Last reset attempt stopped"
        activity = policy == .requireClosed ? "Quitting affected apps…" : "Verifying the reset scope…"
        let succeeded = await doctor.resetAllPermissions(policy: policy, including: clients) { [weak self] update in
            self?.receive(update)
        }
        completed = succeeded
        if succeeded {
            activity = "All \(GlobalRepairPlan().services.count) permission services were reset."
        } else {
            failure = doctor.notice ?? "Reset All stopped. Review the process states and try again."
            activity = "Reset stopped. Review the remaining processes, then retry."
            for index in rows.indices where rows[index].isRunning {
                rows[index].state = .stillRunning
            }
        }
        isApplying = false
        // The store may already be rechecking permission records. In that case
        // monitor() performs this refresh once the check finishes.
        if !succeeded { await refresh() }
    }

    func quit(_ id: ResetAllProcessRow.ID) async {
        guard let index = actionableRow(id), rows[index].process.canRequestTermination else { return }
        do {
            try doctor.quitResetAllProcess(rows[index].process)
            rows[index].state = .quitRequested
            rows[index].detail = nil
        } catch {
            rows[index].detail = error.localizedDescription
        }
    }

    /// Called only after the user confirms the selected process's data-loss
    /// warning. No retry or automatic reset path calls this method.
    func forceQuit(_ id: ResetAllProcessRow.ID) async {
        guard let index = actionableRow(id), rows[index].process.canForceTerminate else { return }
        do {
            try doctor.forceQuitResetAllProcess(rows[index].process)
            rows[index].state = .forceQuitRequested
            rows[index].detail = nil
        } catch {
            rows[index].detail = error.localizedDescription
            failureTitle = "Force Quit failed"
            failure = "Could not force quit \(rows[index].process.name) (PID \(rows[index].process.processIdentifier)). \(error.localizedDescription)"
        }
    }

    private func actionableRow(_ id: ResetAllProcessRow.ID) -> Int? {
        guard !isApplying, !completed, inventoryFailure == nil,
              let index = rows.firstIndex(where: { $0.id == id }), rows[index].isRunning else { return nil }
        return index
    }

    private func receive(_ progress: ResetAllPermissions.Progress) {
        switch progress {
        case .clients(let clients): self.clients.formUnion(clients)
        case .processes(let processes): observe(processes)
        case .quitRequested(let processes):
            let identifiers = Set(processes.map(\.id))
            for index in rows.indices where identifiers.contains(rows[index].process.id) {
                rows[index].state = .quitRequested
            }
        case .resetting(let service): activity = "Resetting \(service.title)…"
        case .verifying(let service): activity = "Verifying \(service.title)…"
        }
    }

    private func observe(_ processes: [AffectedProcess]) {
        let current = processes.map { ResetAllProcessRow(process: $0, state: .running) }
        let liveIDs = Set(current.map(\.id))
        var updated = rows.map { row -> ResetAllProcessRow in
            var row = row
            if !liveIDs.contains(row.id) {
                row.state = .exited
                row.detail = nil
            }
            return row
        }
        for row in current {
            if let index = updated.firstIndex(where: { $0.id == row.id }) {
                let previous = updated[index]
                let state: ResetAllProcessRow.State
                switch previous.state {
                case .quitRequested, .forceQuitRequested, .stillRunning: state = .stillRunning
                default: state = .running
                }
                updated[index] = ResetAllProcessRow(process: row.process, state: state, detail: previous.detail)
            } else {
                updated.append(row)
            }
        }
        rows = updated.sorted {
            if $0.isRunning != $1.isRunning { return $0.isRunning }
            let comparison = $0.process.name.localizedStandardCompare($1.process.name)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            if $0.process.id != $1.process.id { return $0.process.id < $1.process.id }
            return ($0.process.startTime?.seconds ?? 0) < ($1.process.startTime?.seconds ?? 0)
        }
    }
}
