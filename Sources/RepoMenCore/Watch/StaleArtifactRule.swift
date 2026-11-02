import Foundation
import MurtenCore

/// RepoMen's identity and route vocabulary inside the suite.
package enum RepoMenRoutes {
    package static let moduleID = "repomen"
    /// The background check's condition: stale build artifacts in one watched folder.
    package static let staleCondition = "stale-artifacts"
    /// Opens the pane and re-scans, including the named watched folder.
    package static let reviewAction = "review"
    /// The watched folder a review route names (its absolute path).
    package static let folderKey = "folder"
    /// Opens the pane on the auto-trash log.
    package static let logAction = "auto-trash-log"

    /// Evidence keys of a stale-artifacts finding.
    package enum Evidence {
        package static let bytes = "bytes"
        package static let count = "count"
        package static let idleDays = "idleDays"
    }

    /// A review route for `folder`. Paths the route allowlist would reject (too
    /// long, control characters) fall back to a plain review: the pane still
    /// re-scans the configured folders.
    package static func review(folder: String) -> ModuleRoute {
        let acceptable = folder.count <= RouteAllowlist.maximumValueLength
            && !folder.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
        return ModuleRoute(moduleID: moduleID, action: reviewAction,
                           context: acceptable ? [folderKey: folder] : [:])
    }
}

/// Turns a watched folder's stale-artifact total into a suggestion: on at 5 GB,
/// off again only below 4 GB, so a folder hovering at the line does not open and
/// close episodes. The idle threshold itself is the folder's own (30 days unless
/// the user changed it), applied by the watcher.
package struct StaleArtifactRule: SuggestionRule {
    package static let activationBytes: Int64 = 5_000_000_000
    package static let resolutionBytes: Int64 = 4_000_000_000

    private let home: String

    package init(home: String) {
        self.home = home
    }

    package func suggestion(for finding: Finding, state: RuleState) -> SuggestionContent? {
        guard finding.moduleID == RepoMenRoutes.moduleID,
              finding.condition == RepoMenRoutes.staleCondition,
              let bytes = finding.bytes(RepoMenRoutes.Evidence.bytes) else { return nil }
        let threshold = state == .active ? Self.resolutionBytes : Self.activationBytes
        guard bytes >= threshold else { return nil }

        let folder = Format.abbreviatePath(finding.scope.rawValue, home: home)
        let count = finding.count(RepoMenRoutes.Evidence.count) ?? 0
        let artifacts = count == 1 ? "1 build artifact" : "\(count) build artifacts"
        let age = finding.count(RepoMenRoutes.Evidence.idleDays)
            .map { " over \($0) day\($0 == 1 ? "" : "s") ago" } ?? " long ago"
        return SuggestionContent(
            title: "\(Format.bytes(bytes)) of stale build artifacts in \(folder)",
            detail: "\(artifacts) in \(folder) were last built\(age). Open RepoMen to review them; "
                + "nothing is checked or removed until you choose.",
            route: RepoMenRoutes.review(folder: finding.scope.rawValue))
    }
}
