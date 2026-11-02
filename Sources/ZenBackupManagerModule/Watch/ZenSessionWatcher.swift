import Foundation
import MurtenCore
import ZenBackupManagerCore

/// Reports, per Zen profile, how old its newest session snapshot is; the
/// rule decides whether that is worth a suggestion. Observation only: it
/// gets a `SessionSnapshotSource`, never the restore service.
struct ZenSessionWatcher: Watcher {
    let moduleID = ZenBackupRoute.moduleID
    /// Snapshot dates move only when Zen saves and the threshold is days, so
    /// the check is rare work; hourly lets a suggestion resolve soon after
    /// Zen saves again.
    let cadence = WatchCadence(interval: 3600)

    private let source: any SessionSnapshotSource
    private let now: @Sendable () -> Date

    init(source: any SessionSnapshotSource, now: @escaping @Sendable () -> Date = { Date() }) {
        self.source = source
        self.now = now
    }

    func observe() async -> WatchObservation {
        let observedAt = now()

        let profiles: [ZenProfile]
        do {
            profiles = try source.profiles()
        } catch {
            return .unavailable(moduleID: moduleID, at: observedAt, ObservationFailure(
                kind: .failed, message: "Zen's profile list could not be read: \(error.localizedDescription)"))
        }

        var findings: [Finding] = []
        var completed = Set<FindingScope>()
        var failures: [ObservationFailure] = []
        for profile in profiles {
            let scope = FindingScope(profile.id)
            guard !Task.isCancelled else {
                failures.append(ObservationFailure(kind: .failed, scope: scope,
                                                   message: "The check stopped before it reached “\(profile.name)”."))
                continue
            }

            do {
                if let newest = try source.newestSnapshot(in: profile) {
                    findings.append(SessionStalenessRule.finding(for: profile, newestSnapshot: newest, observedAt: observedAt))
                }
                // No snapshot at all is checked and quiet, not stale.
                completed.insert(scope)
            } catch {
                failures.append(ObservationFailure(
                    kind: .failed, scope: scope,
                    message: "The session files of “\(profile.name)” could not be read: \(error.localizedDescription)"))
            }
        }

        // Zen's profile list is every scope that exists, so a profile absent
        // from it is gone: its suggestion resolves even after a relaunch.
        return WatchObservation(moduleID: moduleID, observedAt: observedAt, findings: findings,
                                completedScopes: completed, failures: failures, coverage: .exhaustive)
    }
}
