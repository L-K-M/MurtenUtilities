import Foundation
import MurtenCore

/// Turns a `VerificationFinding` into "Verify <App>'s permissions again".
/// The watcher's signals (a record that no longer reads as granted, a
/// changed signature) cannot prove that the app stopped working, so the
/// suggestion asks for a check, never claims a failure, and opens the pane
/// on that app without starting a reset.
public struct VerificationRule: SuggestionRule {
    public init() {}

    public func suggestion(for finding: Finding, state: RuleState) -> SuggestionContent? {
        guard finding.moduleID == DoctorRoute.moduleID,
              finding.condition == VerificationFinding.condition,
              let appID = UUID(uuidString: finding.scope.rawValue) else { return nil }

        typealias Evidence = VerificationFinding.Evidence
        var reasons: [String] = []
        if let services = finding.text(Evidence.notGranted) {
            reasons.append("macOS reports \(services) as not granted.")
        }
        if finding.text(Evidence.identityChanged) != nil {
            reasons.append("Its signing identity changed since the last check.")
        } else if finding.date(Evidence.unverifiedSince) != nil {
            reasons.append("Its signing identity changed and no passing test was recorded since.")
        }
        guard !reasons.isEmpty else { return nil }

        let name = finding.text(Evidence.appName) ?? "An app"
        let detail = reasons.joined(separator: " ")
            + " A permission record cannot show whether the app works: check it again and test it in DeviceControlDoctor."
        return SuggestionContent(title: "Verify \(name)'s permissions again", detail: detail,
                                 route: DoctorRoute.review(appID: appID))
    }
}
