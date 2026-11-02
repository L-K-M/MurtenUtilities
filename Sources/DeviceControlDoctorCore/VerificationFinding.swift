import Foundation
import MurtenCore

/// The one condition DeviceControlDoctor's watcher reports, scoped to a
/// watched app's watch-list id, and the evidence it carries.
public enum VerificationFinding {
    public static let condition = "needs-verification"

    enum Evidence {
        static let appName = "app"
        /// Titles of the expected permissions that read as not granted.
        static let notGranted = "notGranted"
        static let identityChanged = "identityChanged"
        static let unverifiedSince = "identityUnverifiedSince"
    }

    public static func scope(for appID: UUID) -> FindingScope {
        FindingScope(appID.uuidString)
    }

    /// The finding for `app`, or nil when the assessment raises no concern.
    public static func make(app: WatchedApp, assessment: VerificationAssessment, at date: Date) -> Finding? {
        guard assessment.needsVerification else { return nil }

        var evidence: [String: EvidenceValue] = [Evidence.appName: .text(app.name)]
        if !assessment.notGranted.isEmpty {
            evidence[Evidence.notGranted] = .text(assessment.notGranted.map(\.title).joined(separator: ", "))
        }
        switch assessment.identity {
        case .changed:
            evidence[Evidence.identityChanged] = .text("changed")
        case .unverified(let since):
            evidence[Evidence.unverifiedSince] = .date(since)
        case nil:
            break
        }

        return Finding(moduleID: DoctorRoute.moduleID, condition: condition, scope: scope(for: app.id),
                       observedAt: date, evidence: evidence)
    }
}
