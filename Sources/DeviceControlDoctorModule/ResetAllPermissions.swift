import DoctorCore
import Foundation

/// Performs the deliberately broad reset only after every recorded client is
/// known and its matching processes have stayed closed. The watcher never
/// reaches this type; only the Reset All confirmation does.
@MainActor
struct ResetAllPermissions {
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

    func inspect() async throws -> Preparation {
        do {
            try await requireClientListing()
            let scope = try await readScope()
            let running = try await lifecycle.runningProcesses(matching: scope.clients)
            return Preparation(clients: scope.clients, runningProcesses: running)
        } catch let error where !(error is CancellationError) {
            throw ResetAllError.stopped(error, .nothingReset)
        }
    }

    func apply() async -> Result {
        var outcomes: [Outcome] = []
        do {
            try Task.checkCancellation()
            try await requireClientListing()
            var scope = try await readScope()
            var knownClients = scope.clients
            guard !knownClients.isEmpty else {
                return Result(outcomes: [], failure: "There are no Device Control and Data Access settings to reset.")
            }

            try await quiesce(knownClients)

            // Re-read after quitting. An app may have created or removed a
            // record while responding to the quit request.
            scope = try await readScope()
            knownClients.formUnion(scope.clients)
            try await quiesce(knownClients)

            let plan = GlobalRepairPlan()
            for (service, arguments) in zip(plan.services, plan.arguments) {
                try Task.checkCancellation()

                // The TCC scope shrinks after each successful reset. Preserve
                // every client ever observed so one of those apps cannot
                // relaunch and disappear from later safety checks.
                let currentScope = try await readScope()
                knownClients.formUnion(currentScope.clients)
                try await verifyStableAndClosed(service: service, knownClients: &knownClients)

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
    private func verifyStableAndClosed(service: PermissionService,
                                       knownClients: inout Set<String>) async throws {
        for _ in 0..<3 {
            try Task.checkCancellation()
            let before = try await readClients(for: service)
            knownClients.formUnion(before)
            let running = try await lifecycle.runningProcesses(matching: knownClients)
            guard running.isEmpty else {
                throw ResetAllError.appsStillRunning(running)
            }
            let after = try await readClients(for: service)
            knownClients.formUnion(after)
            let runningAfter = try await lifecycle.runningProcesses(matching: knownClients)
            guard runningAfter.isEmpty else {
                throw ResetAllError.appsStillRunning(runningAfter)
            }
            if before == after { return }
        }
        throw ResetAllError.clientListUnstable(service)
    }

    private func quiesce(_ clients: Set<String>) async throws {
        var stableSamples = 0
        var lastRunning: [AffectedProcess] = []

        for _ in 0..<timing.maximumPolls {
            try Task.checkCancellation()
            let running = try await lifecycle.runningProcesses(matching: clients)
            if running.isEmpty {
                stableSamples += 1
                if stableSamples >= timing.stableSamples { return }
            } else {
                stableSamples = 0
                lastRunning = running
                lifecycle.requestTermination(of: running)
            }
            try await Task.sleep(nanoseconds: timing.pollNanoseconds)
        }
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
            let names = processes.isEmpty ? "An affected app" : processes.map(\.name).joined(separator: ", ")
            return "\(names) \(processes.count == 1 ? "is" : "are") still running. Quit every affected app and try again."
        case .stopped(let error, let progress):
            return "\(error.localizedDescription) \(progress.consequence)"
        }
    }
}
