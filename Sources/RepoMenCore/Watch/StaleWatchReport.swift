import Foundation
import MurtenCore

/// What the background check needs from RepoMen's settings, snapshotted on the
/// main actor before a poll. It covers the folders the pane scans (Settings ›
/// Folders, idle after `scanRootIdleDays`) and the watched folders (Settings ›
/// Watch, each with its own threshold); a path in both follows its watched entry.
package struct StaleWatchSettings: Equatable, Sendable {
    /// Every watched folder; disabled ones are not scanned.
    package var folders: [WatchedFolder]
    /// The pane's scan folders.
    package var scanRoots: [String]
    /// The pane's idle threshold ("Select Idle"), applied to the scan folders.
    package var scanRootIdleDays: Int
    /// Folders no longer scanned or watched. Reported as checked, so a
    /// suggestion about one resolves instead of lingering.
    package var retiredPaths: [String]
    package var excludedPaths: Set<String>
    package var enabledKinds: Set<ArtifactKind>

    package init(folders: [WatchedFolder], scanRoots: [String] = [], scanRootIdleDays: Int = 30,
                 retiredPaths: [String] = [], excludedPaths: Set<String> = [],
                 enabledKinds: Set<ArtifactKind> = Set(ArtifactKind.allCases)) {
        self.folders = folders
        self.scanRoots = scanRoots
        self.scanRootIdleDays = scanRootIdleDays
        self.retiredPaths = retiredPaths
        self.excludedPaths = excludedPaths
        self.enabledKinds = enabledKinds
    }

    /// The folders a background check surveys, each with its idle threshold:
    /// enabled watched folders, then scan folders not already watched.
    package var surveyedFolders: [WatchedFolder] {
        let watched = Set(folders.map(\.path))
        var seen = Set<String>()
        let scanned = scanRoots
            .filter { !watched.contains($0) && seen.insert($0).inserted }
            .map { WatchedFolder(path: $0, maxIdleDays: scanRootIdleDays) }
        return folders.filter(\.isEnabled) + scanned
    }

    /// Paused watched folders and retired paths that are not surveyed.
    package var unsurveyedPaths: [String] {
        let surveyed = Set(surveyedFolders.map(\.path))
        var seen = Set<String>()
        return (folders.filter { !$0.isEnabled }.map(\.path) + retiredPaths)
            .filter { !surveyed.contains($0) && seen.insert($0).inserted }
    }
}

/// One watched folder's result in a background survey.
package enum WatchRootStatus: Equatable, Sendable {
    case surveyed(StaleArtifactTotals)
    case refused(WatchRootRefusal)
}

/// Turns a survey into the suite's `WatchObservation`: one finding per scanned
/// folder, one failure per folder that could not be scanned, and the folders no
/// longer surveyed as completed scopes without findings.
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

        for folder in settings.surveyedFolders {
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

        // Not surveyed (any more): nothing there is RepoMen's to report, so the
        // scope counts as checked and an old suggestion for it resolves.
        for path in settings.unsurveyedPaths {
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
