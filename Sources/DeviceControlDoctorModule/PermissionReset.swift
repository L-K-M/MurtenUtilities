import Foundation
import DoctorCore

/// Runs a confirmed `RepairPlan`: one `tccutil reset SERVICE BUNDLE_ID` per
/// selected service. Only the repair sheet's confirmation reaches this;
/// pane monitoring and the background check never do.
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
            let failure: String?
            if result.outputTruncated {
                failure = "The reset returned more output than could be verified; its outcome is uncertain. Check System Settings."
            } else if result.timedOut {
                failure = "The reset timed out; its outcome is uncertain. Check System Settings."
            } else if result.exitCode != 0 {
                failure = result.output.isEmpty
                    ? "tccutil returned exit code \(result.exitCode)."
                    : String(result.output.prefix(600))
            } else {
                failure = nil
            }
            outcomes.append(Outcome(service: service, failure: failure))
        }
        return outcomes
    }
}
