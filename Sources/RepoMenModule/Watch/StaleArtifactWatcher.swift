import Foundation
import MurtenCore
import RepoMenCore

/// The background check's only view of the disk: it surveys watched folders and
/// returns totals. It has no way to trash, delete or prompt; the pane and armed
/// auto-trash hold those powers, not this.
protocol StaleArtifactObserving: Sendable {
    /// One status per surveyed folder in `settings`; nil when cancelled.
    func survey(_ settings: StaleWatchSettings, now: Date) async -> [String: WatchRootStatus]?
}

/// The live survey: unprivileged reads, privacy-protected folders refused before
/// anything inside them is touched (`StaleArtifactSurvey`).
struct LiveStaleArtifactObserver: StaleArtifactObserving {
    func survey(_ settings: StaleWatchSettings, now: Date) async -> [String: WatchRootStatus]? {
        let protectedRoots = ProtectedLocations.current
        let folders = settings.surveyedFolders
        let (admitted, refused) = StaleArtifactSurvey.admit(folders, protectedRoots: protectedRoots)
        guard let stale = await StaleArtifactSurvey.staleItems(
            in: admitted, governedBy: folders,
            excludedPaths: settings.excludedPaths, enabledKinds: settings.enabledKinds,
            protectedRoots: protectedRoots, now: now) else { return nil }

        var statuses: [String: WatchRootStatus] = refused.mapValues { .refused($0) }
        for folder in admitted {
            statuses[folder.path] = .surveyed(StaleArtifactSurvey.totals(of: stale[folder.path] ?? []))
        }
        return statuses
    }
}

/// RepoMen's background check: every 6 hours (the standalone app's watch
/// interval), how many bytes of build artifacts in each scan folder and watched
/// folder are idle past that folder's threshold. It only looks; acting on the
/// result is the pane's job, or armed auto-trash's on its own schedule.
struct StaleArtifactWatcher: Watcher {
    /// A walk 16 levels deep that sizes every artifact can take minutes on a
    /// large tree, so the timeout is far above the suite's 60 s default.
    static let defaultCadence = WatchCadence(interval: AutoTrash.interval, timeout: 30 * 60)

    let moduleID = RepoMenRoutes.moduleID
    let cadence = StaleArtifactWatcher.defaultCadence

    private let observer: any StaleArtifactObserving
    private let settings: @Sendable () async -> StaleWatchSettings
    private let now: @Sendable () -> Date
    private let home: String

    init(observer: any StaleArtifactObserving = LiveStaleArtifactObserver(),
         settings: @escaping @Sendable () async -> StaleWatchSettings,
         now: @escaping @Sendable () -> Date = { Date() },
         home: String = NSHomeDirectory()) {
        self.observer = observer
        self.settings = settings
        self.now = now
        self.home = home
    }

    func observe() async -> WatchObservation {
        let snapshot = await settings()
        let startedAt = now()
        let statuses = await observer.survey(snapshot, now: startedAt)
        let statusesIfFinished = Task.isCancelled ? nil : statuses
        return StaleWatchReport.observation(settings: snapshot, statuses: statusesIfFinished,
                                            at: startedAt, home: home)
    }
}
