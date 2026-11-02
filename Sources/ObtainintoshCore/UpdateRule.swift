import Foundation
import MurtenCore

/// Suggests a program whose latest release is newer than the installed copy,
/// judged with the same comparison as the pane's "Update Available" badge.
/// No hysteresis: a version is newer or it is not. A newer release of a
/// program already suggested refreshes the suggestion's text without opening
/// a new episode.
public struct UpdateRule: SuggestionRule {
    public init() {}

    public func suggestion(for finding: Finding, state: RuleState) -> SuggestionContent? {
        guard finding.moduleID == UpdateFinding.moduleID, finding.condition == UpdateFinding.condition,
              let name = finding.text(UpdateFinding.Evidence.name),
              let installed = finding.text(UpdateFinding.Evidence.installed),
              let latest = finding.text(UpdateFinding.Evidence.latest),
              VersionComparison.hasUpdate(current: installed, latest: latest) else { return nil }

        return SuggestionContent(
            title: "\(name) \(latest) is available",
            detail: "Version \(installed) is installed. Obtainintosh downloads the release and shows it in Finder; "
                + "you install it yourself.",
            route: ModuleRoute(moduleID: UpdateFinding.moduleID, action: UpdateFinding.routeAction))
    }
}
