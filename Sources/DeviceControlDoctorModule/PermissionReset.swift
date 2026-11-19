import Foundation
import DoctorCore

/// Runs a confirmed `RepairPlan` or `InventoryResetPlan`: one
/// `tccutil reset SERVICE BUNDLE_ID` per selected service. Only a reset
/// sheet's confirmation reaches this; pane monitoring and the background
/// check never do.
struct PermissionReset {
    struct Outcome: Equatable {
        let service: ResetService
        /// nil when tccutil reported success, not proof of cleared entries or
        /// effective access. Organization policy may still allow or deny access.
        let failure: String?
    }

    let runner: any ProcessRunning

    func apply(_ plan: RepairPlan) async -> [Outcome] {
        var outcomes: [Outcome] = []
        for (service, arguments) in zip(plan.services, plan.arguments) {
            let result = await runner.run(SystemTool.tccutil, arguments)
            outcomes.append(Outcome(service: service, failure: Self.failure(of: result)))
        }
        return outcomes
    }

    /// Runs a confirmed inventory reset. Returns the failure of every
    /// command that did not report success, by `InventoryResetResult.commandKey`.
    func apply(_ plans: [InventoryResetPlan]) async -> [String: String] {
        var failures: [String: String] = [:]
        for plan in plans {
            for (service, arguments) in zip(plan.services, plan.arguments) {
                let result = await runner.run(SystemTool.tccutil, arguments)
                if let failure = Self.failure(of: result) {
                    failures[InventoryResetResult.commandKey(bundleIdentifier: plan.bundleIdentifier, service: service)] = failure
                }
            }
        }
        return failures
    }

    /// nil when tccutil reported success; otherwise what it said.
    static func failure(of result: CommandResult) -> String? {
        if result.outputTruncated {
            return "The reset returned more output than could be verified; its outcome is uncertain. Check System Settings."
        }
        if result.timedOut {
            return "The reset timed out; its outcome is uncertain. Check System Settings."
        }
        guard result.exitCode != 0 else { return nil }
        return result.output.isEmpty
            ? "tccutil returned exit code \(result.exitCode)."
            : String(result.output.prefix(600))
    }
}
