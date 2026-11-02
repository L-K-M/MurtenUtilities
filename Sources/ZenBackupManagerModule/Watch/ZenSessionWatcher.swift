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
    private let seen = SeenProfiles()

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

        // A profile that left Zen's list was checked and is gone, so its
        // suggestion resolves. The ledger does not tell a watcher which scopes
        // are active, so only profiles listed since launch can be named.
        completed.formUnion(seen.departed(listed: Set(profiles.map { FindingScope($0.id) })))

        return WatchObservation(moduleID: moduleID, observedAt: observedAt, findings: findings,
                                completedScopes: completed, failures: failures)
    }
}

/// Profiles the watcher has listed since launch. A reference, so every copy
/// of the watcher value shares it.
private final class SeenProfiles: @unchecked Sendable {
    private let lock = NSLock()
    private var scopes = Set<FindingScope>()

    /// Records `listed` and returns the profiles seen before but not listed now.
    func departed(listed: Set<FindingScope>) -> Set<FindingScope> {
        lock.lock()
        defer { lock.unlock() }
        scopes.formUnion(listed)
        return scopes.subtracting(listed)
    }
}
