import Foundation
import MurtenCore

/// What the background check needs from RepoMen's settings, snapshotted on the
/// main actor before a poll.
package struct StaleWatchSettings: Equatable, Sendable {
    /// Every watched folder; disabled ones are not scanned.
    package var folders: [WatchedFolder]
    /// Folders the user stopped watching. Reported as checked, so a suggestion
    /// about one resolves instead of lingering.
    package var retiredPaths: [String]
    package var excludedPaths: Set<String>
    package var enabledKinds: Set<ArtifactKind>

    package init(folders: [WatchedFolder], retiredPaths: [String] = [],
                 excludedPaths: Set<String> = [], enabledKinds: Set<ArtifactKind> = Set(ArtifactKind.allCases)) {
        self.folders = folders
        self.retiredPaths = retiredPaths
        self.excludedPaths = excludedPaths
        self.enabledKinds = enabledKinds
    }
}

/// One watched folder's result in a background survey.
package enum WatchRootStatus: Equatable, Sendable {
    case surveyed(StaleArtifactTotals)
    case refused(WatchRootRefusal)
}

/// Turns a survey into the suite's `WatchObservation`: one finding per scanned
/// folder, one failure per folder that could not be scanned, and the folders no
/// longer watched as completed scopes without findings.
package enum StaleWatchReport {

    package static func observation(settings: StaleWatchSettings,
                                    statuses: [String: WatchRootStatus]?,
                                    at date: Date,
                                    home: String) -> WatchObservation {
        let moduleID = RepoMenRoutes.moduleID
        guard let statuses else {
            return .unavailable(moduleID: moduleID, at: date,
                                ObservationFailure(kind: .failed, message: "The check was stopped before it finished."))
        }

        var findings: [Finding] = []
        var completed = Set<FindingScope>()
        var failures: [ObservationFailure] = []
        let enabled = settings.folders.filter(\.isEnabled)

        for folder in enabled {
            let scope = FindingScope(folder.path)
            switch statuses[folder.path] {
            case .surveyed(let totals)?:
                completed.insert(scope)
                findings.append(Finding(
                    moduleID: moduleID, condition: RepoMenRoutes.staleCondition, scope: scope,
                    observedAt: date,
                    evidence: [RepoMenRoutes.Evidence.bytes: .bytes(totals.bytes),
                               RepoMenRoutes.Evidence.count: .count(totals.count),
                               RepoMenRoutes.Evidence.idleDays: .count(folder.maxIdleDays)]))
            case .refused(let refusal)?:
                failures.append(failure(for: refusal, scope: scope, path: folder.path, home: home))
            case nil:
                failures.append(ObservationFailure(
                    kind: .failed, scope: scope,
                    message: "\(Format.abbreviatePath(folder.path, home: home)) was not checked."))
            }
        }

        // Not watched (any more): nothing there is RepoMen's to report, so the
        // scope counts as checked and an old suggestion for it resolves.
        let watched = Set(enabled.map(\.path))
        let unwatched = settings.folders.filter { !$0.isEnabled }.map(\.path) + settings.retiredPaths
        for path in unwatched where !watched.contains(path) {
            completed.insert(FindingScope(path))
        }

        return WatchObservation(moduleID: moduleID, observedAt: date, findings: findings,
                                completedScopes: completed, failures: failures)
    }

    private static func failure(for refusal: WatchRootRefusal, scope: FindingScope,
                                path: String, home: String) -> ObservationFailure {
        let folder = Format.abbreviatePath(path, home: home)
        switch refusal {
        case .protected(let root):
            return ObservationFailure(
                kind: .permissionDenied, scope: scope,
                message: "\(folder) is inside \(Format.abbreviatePath(root, home: home)), which macOS "
                    + "protects with a privacy prompt. Background checks skip it; scan it in RepoMen instead.")
        case .missing:
            return ObservationFailure(kind: .toolMissing, scope: scope,
                                      message: "The watched folder \(folder) no longer exists.")
        case .unreadable(let permissionDenied, let reason):
            return ObservationFailure(kind: permissionDenied ? .permissionDenied : .failed, scope: scope,
                                      message: "\(folder) could not be read: \(reason)")
        case .unresolvable:
            return ObservationFailure(kind: .failed, scope: scope,
                                      message: "\(folder) has too many symbolic links to follow.")
        }
    }
}
