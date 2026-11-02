import Foundation
import MurtenCore

/// What the background check reports about one installed program: its
/// installed and latest versions. One finding per program, scoped by the
/// entry's id, so programs open, snooze and resolve independently.
public enum UpdateFinding {
    public static let moduleID = "obtainintosh"
    public static let condition = "release-status"
    /// The route a suggestion opens: the pane, which checks again.
    public static let routeAction = "updates"

    enum Evidence {
        static let name = "name"
        static let installed = "installed"
        static let latest = "latest"
    }

    public static func scope(forAppID id: String) -> FindingScope {
        FindingScope(id)
    }

    public static func make(app: TrackedApp, installed: String, latest: String, at date: Date) -> Finding {
        Finding(moduleID: moduleID, condition: condition, scope: scope(forAppID: app.id), observedAt: date,
                evidence: [Evidence.name: .text(app.name), Evidence.installed: .text(installed),
                           Evidence.latest: .text(latest)])
    }
}
