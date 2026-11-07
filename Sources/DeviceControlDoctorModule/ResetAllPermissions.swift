import DoctorCore
import Foundation

/// Performs the broad reset with a verified client scope. Requiring closed
/// apps is the default; only the explicit risk acknowledgement bypasses that
/// requirement. The watcher never reaches this repair coordinator.
@MainActor
struct ResetAllPermissions {
    enum RunningAppsPolicy: Sendable {
        case requireClosed
        case allowRunning
    }

    enum Progress {
        case clients(Set<String>)
        case processes([AffectedProcess])
        case quitRequested([AffectedProcess])
        case resetting(PermissionService)
        case verifying(PermissionService)
    }

    struct Preparation: Equatable, Sendable {
        let clients: Set<String>
        let runningProcesses: [AffectedProcess]
    }

    struct Outcome: Equatable, Sendable {
        let service: PermissionService
        let failure: String?
    }

    struct Result: Equatable, Sendable {
        let outcomes: [Outcome]
        let failure: String?

        var succeeded: Bool {
            failure == nil
                && outcomes.count == PermissionService.allCases.count
                && outcomes.allSatisfy { $0.failure == nil }
        }
    }

    struct Timing: Sendable {
        let pollNanoseconds: UInt64
        let stableSamples: Int
        let maximumPolls: Int

        static let live = Timing(pollNanoseconds: 200_000_000, stableSamples: 5, maximumPolls: 40)
    }

    private struct Scope {
        let clientsByService: [PermissionService: Set<String>]
        var clients: Set<String> {
            clientsByService.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        }
    }

    let runner: any ProcessRunning
    let lifecycle: any ApplicationLifecycleManaging
    let timing: Timing

    init(runner: any ProcessRunning, lifecycle: any ApplicationLifecycleManaging, timing: Timing = .live) {
        self.runner = runner
        self.lifecycle = lifecycle
        self.timing = timing
    }

    func inspect(including knownClients: Set<String> = []) async throws -> Preparation {
        do {
            try await requireClientListing()
            let scope = try await readScope()
            let clients = scope.clients.union(knownClients)
            let running = try await lifecycle.runningProcesses(matching: clients)
            return Preparation(clients: clients, runningProcesses: running)
        } catch let error where !(error is CancellationError) {
            throw ResetAllError.stopped(error, .nothingReset)
        }
    }

    func apply(policy: RunningAppsPolicy = .requireClosed,
               including previouslyKnownClients: Set<String> = [],
               progress: @MainActor (Progress) -> Void = { _ in }) async -> Result {
        var outcomes: [Outcome] = []
        do {
            try Task.checkCancellation()
            try await requireClientListing()
            var scope = try await readScope()
            var knownClients = scope.clients.union(previouslyKnownClients)
            progress(.clients(knownClients))
            guard !scope.clients.isEmpty else {
                return Result(outcomes: [], failure: "There are no Device Control and Data Access settings to reset.")
            }

            try await prepareProcesses(knownClients, policy: policy, progress: progress)

            // Re-read after quitting. An app may have created or removed a
            // record while responding to the quit request.
            scope = try await readScope()
            knownClients.formUnion(scope.clients)
            progress(.clients(knownClients))
            try await prepareProcesses(knownClients, policy: policy, progress: progress)

            let plan = GlobalRepairPlan()
            for (service, arguments) in zip(plan.services, plan.arguments) {
                try Task.checkCancellation()

                // The TCC scope shrinks after each successful reset. Preserve
                // every client ever observed so one of those apps cannot
                // relaunch and disappear from later safety checks.
                let currentScope = try await readScope()
                knownClients.formUnion(currentScope.clients)
                progress(.clients(knownClients))
                try await verifyStableScope(service: service, knownClients: &knownClients,
                                            policy: policy, progress: progress)

                progress(.resetting(service))
                let command = await runner.run(SystemTool.tccutil, arguments)
                let failure: String?
                if command.outputTruncated {
                    failure = "The reset returned more output than could be verified; its outcome is uncertain. Check System Settings."
                } else if command.timedOut {
                    failure = "The reset timed out; its outcome is uncertain. Check System Settings."
                } else if command.exitCode != 0 {
                    failure = command.output.isEmpty
                        ? "tccutil returned exit code \(command.exitCode)."
                        : String(command.output.prefix(600))
                } else {
                    failure = nil
                }
                if let failure {
                    outcomes.append(Outcome(service: service, failure: failure))
                    return Result(outcomes: outcomes,
                                  failure: "\(service.title): \(failure) No further permissions were reset.")
                }

                // The command may already have changed TCC, but it is not a
                // completed reset until a fresh query proves the service is
                // empty. Keep an explicit uncertain outcome if that query
                // throws, times out, or is cancelled.
                outcomes.append(Outcome(
                    service: service,
                    failure: "The reset command completed, but its result could not be verified."
                ))
                progress(.verifying(service))
                let remaining = try await readClients(for: service)
                guard remaining.isEmpty else {
                    knownClients.formUnion(remaining)
                    let failure = "The client list was not empty after reset. No further permissions were reset."
                    outcomes[outcomes.count - 1] = Outcome(service: service, failure: failure)
                    return Result(outcomes: outcomes, failure: "\(service.title): \(failure)")
                }
                outcomes[outcomes.count - 1] = Outcome(service: service, failure: nil)
            }
        } catch is CancellationError {
            return Result(outcomes: outcomes, failure: "Reset All was cancelled. Completed service resets cannot be undone.")
        } catch {
            // An outcome is recorded only once its reset command has run.
            let progress: ResetAllError.Progress = outcomes.isEmpty ? .nothingReset : .resetsAttempted
            return Result(outcomes: outcomes,
                          failure: ResetAllError.stopped(error, progress).localizedDescription)
        }

        let failures = outcomes.compactMap { outcome in
            outcome.failure.map { "\(outcome.service.title): \($0)" }
        }
        return Result(outcomes: outcomes, failure: failures.isEmpty ? nil : failures.joined(separator: "\n"))
    }

    private func requireClientListing() async throws {
        let help = await runner.run(SystemTool.tccutil, [])
        guard !help.timedOut, TCCOutputParser.supportsListing(help: help.output) else {
            throw ResetAllError.clientListUnavailable
        }
    }

    private func readScope() async throws -> Scope {
        var clientsByService: [PermissionService: Set<String>] = [:]
        for service in PermissionService.allCases {
            try Task.checkCancellation()
            clientsByService[service] = try await readClients(for: service)
        }
        return Scope(clientsByService: clientsByService)
    }

    private func readClients(for service: PermissionService) async throws -> Set<String> {
        let command = await runner.run(SystemTool.tccutil, ["list", "-s", service.rawValue])
        guard !command.outputTruncated, !command.timedOut, command.exitCode == 0 else {
            throw ResetAllError.clientListFailed(service, command)
        }

        var clients = Set<String>()
        let headings: Set<String> = ["granted:", "denied:", "limited:"]
        for line in command.output.components(separatedBy: .newlines) {
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            if ClientIdentifier.isBundleIdentifier(value)
                || (value.hasPrefix("/") && !value.hasPrefix("//")) {
                clients.insert(value)
            } else if !headings.contains(value.lowercased()) {
                throw ResetAllError.clientListMalformed(service, value)
            }
        }
        return clients
    }

    /// Brackets a complete process inventory with two target-service reads.
    /// If the service scope changes while processes are being inspected, try
    /// again with the expanded cumulative client set instead of mutating from
    /// a stale snapshot.
    private func verifyStableScope(service: PermissionService, knownClients: inout Set<String>,
                                   policy: RunningAppsPolicy,
                                   progress: @MainActor (Progress) -> Void) async throws {
        for _ in 0..<3 {
            try Task.checkCancellation()
            let before = try await readClients(for: service)
            knownClients.formUnion(before)
            progress(.clients(knownClients))
            let running = try await lifecycle.runningProcesses(matching: knownClients)
            progress(.processes(running))
            guard policy == .allowRunning || running.isEmpty else {
                throw ResetAllError.appsStillRunning(running)
            }
            let after = try await readClients(for: service)
            knownClients.formUnion(after)
            progress(.clients(knownClients))
            let runningAfter = try await lifecycle.runningProcesses(matching: knownClients)
            progress(.processes(runningAfter))
            guard policy == .allowRunning || runningAfter.isEmpty else {
                throw ResetAllError.appsStillRunning(runningAfter)
            }
            if before == after { return }
        }
        throw ResetAllError.clientListUnstable(service)
    }

    private func prepareProcesses(_ clients: Set<String>, policy: RunningAppsPolicy,
                                  progress: @MainActor (Progress) -> Void) async throws {
        try Task.checkCancellation()
        if policy == .allowRunning {
            // Acknowledgement waives only quiescence, never inventory or scope
            // verification. It does not silently quit or force-kill anything.
            progress(.processes(try await lifecycle.runningProcesses(matching: clients)))
            return
        }

        var stableSamples = 0
        var lastRunning: [AffectedProcess] = []

        for _ in 0..<timing.maximumPolls {
            try Task.checkCancellation()
            let running = try await lifecycle.runningProcesses(matching: clients)
            progress(.processes(running))
            if running.isEmpty {
                stableSamples += 1
                if stableSamples >= timing.stableSamples { return }
            } else {
                stableSamples = 0
                lastRunning = running
                lifecycle.requestTermination(of: running)
                progress(.quitRequested(running.filter(\.canRequestTermination)))
            }
            try await Task.sleep(nanoseconds: timing.pollNanoseconds)
        }
        if stableSamples > 0 || lastRunning.isEmpty { throw ResetAllError.appsNotStable }
        throw ResetAllError.appsStillRunning(lastRunning)
    }
}

private enum ResetAllError: LocalizedError {
    /// What a stopped run had already changed, for its closing sentence.
    enum Progress {
        case nothingReset
        case resetsAttempted

        var consequence: String {
            switch self {
            case .nothingReset: return "No permissions were reset."
            case .resetsAttempted: return "No further permissions were reset."
            }
        }
    }

    case clientListUnavailable
    case clientListFailed(PermissionService, CommandResult)
    case clientListMalformed(PermissionService, String)
    case clientListUnstable(PermissionService)
    case appsStillRunning([AffectedProcess])
    case appsNotStable
    case stopped(any Error, Progress)

    var errorDescription: String? {
        switch self {
        case .clientListUnavailable:
            return "This Mac cannot provide the complete Device Control and Data Access client list. Reset All is disabled because affected apps cannot be verified."
        case .clientListFailed(let service, let command):
            let detail: String
            if command.outputTruncated {
                detail = "The query output was truncated."
            } else if command.timedOut {
                detail = "The query timed out."
            } else {
                detail = String(command.output.prefix(300))
            }
            let summary = "The \(service.title) client list could not be read."
            return detail.isEmpty ? summary : "\(summary) \(detail)"
        case .clientListMalformed(let service, let line):
            return "The \(service.title) client list contained an unrecognized record (\(String(line.prefix(160))))."
        case .clientListUnstable(let service):
            return "The \(service.title) client list kept changing during the safety check."
        case .appsStillRunning(let processes):
            let count = processes.count
            let subject = count == 1 ? "1 affected process is" : "\(count) affected processes are"
            return "\(subject) still running. Review their status below, quit them, and retry. Force Quit is never automatic."
        case .appsNotStable:
            return "Affected processes have not stayed closed long enough. Review their status and retry."
        case .stopped(let error, let progress):
            return "\(error.localizedDescription) \(progress.consequence)"
        }
    }
}
