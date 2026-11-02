import Foundation
import DoctorCore

/// Runs a confirmed `RepairPlan`: one `tccutil reset SERVICE BUNDLE_ID` per
/// selected service. Only the repair sheet's confirmation reaches this;
/// pane monitoring and the background check never do.
struct PermissionReset {
    struct Outcome: Equatable {
        let service: PermissionService
        /// nil when the reset reported success; otherwise why it did not.
        let failure: String?
    }

    let runner: any ProcessRunning

    func apply(_ plan: RepairPlan) async -> [Outcome] {
        var outcomes: [Outcome] = []
        for (service, arguments) in zip(plan.services, plan.arguments) {
            let result = await runner.run(SystemTool.tccutil, arguments)
            if result.exitCode == 0 && !result.timedOut {
                outcomes.append(Outcome(service: service, failure: nil))
            } else {
                let detail = result.timedOut ? "The reset timed out; its outcome is uncertain. Check System Settings." : String(result.output.prefix(600))
                outcomes.append(Outcome(service: service, failure: detail))
            }
        }
        return outcomes
    }
}
