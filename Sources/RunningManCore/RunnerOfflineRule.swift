import Foundation
import MurtenCore

/// RunningMan's threshold: a runner offline for 10 minutes or more becomes
/// "<runner> has been offline for N min — restart?". Hysteresis: once open, the
/// suggestion stays until the runner is online again (the check then reports the
/// runner's scope without a finding), so a runner hovering around the threshold
/// does not open and close episodes. The minutes in the title change within one
/// episode; they never open a new one.
public struct RunnerOfflineRule: SuggestionRule {
    public static let threshold: TimeInterval = 10 * 60
    /// The route action that opens the pane on one runner, and its context key.
    public static let routeAction = "runner"
    public static let runnerContextKey = "id"

    public init() {}

    public func suggestion(for finding: Finding, state: RuleState) -> SuggestionContent? {
        guard finding.condition == RunnerHealthCheck.condition,
              let offlineSince = finding.date(RunnerHealthCheck.Evidence.offlineSince) else { return nil }

        let offline = max(0, finding.observedAt.timeIntervalSince(offlineSince))
        guard state == .active || offline >= Self.threshold else { return nil }

        let name = finding.text(RunnerHealthCheck.Evidence.name)
            ?? URL(fileURLWithPath: finding.scope.rawValue).lastPathComponent
        let minutes = Int(offline / 60)
        let reason = finding.text(RunnerHealthCheck.Evidence.reason).flatMap(RunnerHealthCheck.Reason.init(rawValue:))
        let cause = reason == .startsAtLogin
            ? "It is set to start at login but is not running."
            : "It stopped without a request from CI Runner Manager."

        return SuggestionContent(
            title: "\(name) has been offline for \(minutes) min — restart?",
            detail: cause + " Open CI Runner Manager to check its logs and start it; nothing restarts until you choose Start.",
            route: Self.route(forRunner: finding.scope.rawValue))
    }

    /// Opens the pane on the runner. An identifier too long for a route opens the
    /// runner list instead of a link the suite would reject.
    public static func route(forRunner runnerID: String) -> ModuleRoute {
        let context = runnerID.count <= RouteAllowlist.maximumValueLength ? [runnerContextKey: runnerID] : [:]
        return ModuleRoute(moduleID: RunnerHealthCheck.moduleID, action: routeAction, context: context)
    }
}
