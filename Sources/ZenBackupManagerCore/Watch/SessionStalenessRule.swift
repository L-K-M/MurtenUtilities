import Foundation
import MurtenCore

/// Suggests the timeline when a profile's newest session snapshot is a week
/// old or more.
///
/// Zen writes these snapshots itself while it runs. An old newest snapshot
/// therefore means Zen has not saved a session for that profile: it has not
/// been used, or it crashes before it saves. It never means a backup is
/// overdue; this module schedules no backups, and the wording says so.
///
/// The age only grows until Zen saves again, which drops it to minutes, so
/// the rule needs no hysteresis band. The day count in the title changes as
/// the age grows; that refreshes the suggestion without opening a new episode.
public struct SessionStalenessRule: SuggestionRule {
    public static let condition = "session-stale"
    public static let threshold: TimeInterval = 7 * secondsPerDay

    private static let secondsPerDay: TimeInterval = 24 * 3600

    /// Evidence the watcher reports and the rule reads.
    enum Evidence {
        static let age = "age"
        static let newestSnapshot = "newestSnapshot"
        static let profileName = "profileName"
    }

    public init() {}

    /// The finding for one profile whose newest snapshot is dated
    /// `newestSnapshot`. Scoped by the profile's directory, so two profiles
    /// never share a suggestion.
    public static func finding(for profile: ZenProfile, newestSnapshot: Date, observedAt: Date) -> Finding {
        Finding(moduleID: ZenBackupRoute.moduleID, condition: condition, scope: FindingScope(profile.id),
                observedAt: observedAt,
                evidence: [
                    Evidence.age: .seconds(max(0, observedAt.timeIntervalSince(newestSnapshot))),
                    Evidence.newestSnapshot: .date(newestSnapshot),
                    Evidence.profileName: .text(profile.name),
                ])
    }

    public func suggestion(for finding: Finding, state: RuleState) -> SuggestionContent? {
        guard finding.condition == Self.condition, let age = finding.seconds(Evidence.age),
              age >= Self.threshold else { return nil }

        let days = Int(age / Self.secondsPerDay)
        let profile = finding.text(Evidence.profileName) ?? finding.scope.rawValue
        return SuggestionContent(
            title: "Zen has not saved a session in \(days) days",
            detail: "The newest session snapshot of the Zen profile “\(profile)” is \(days) days old. "
                + "Zen writes these snapshots itself while it runs, so it has not been used with this profile, "
                + "or it is crashing before it saves. Open the timeline to see which sessions you can return to.",
            route: ModuleRoute(moduleID: ZenBackupRoute.moduleID, action: ZenBackupRoute.timelineAction,
                               context: Self.routeContext(for: finding.scope)))
    }

    /// Names the profile when the route allowlist accepts its path; a longer
    /// path opens the timeline on the default profile instead of a link the
    /// suite would reject.
    private static func routeContext(for scope: FindingScope) -> [String: String] {
        let path = scope.rawValue
        let acceptable = path.count <= RouteAllowlist.maximumValueLength
            && !path.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
        return acceptable ? [ZenBackupRoute.profileKey: path] : [:]
    }
}
