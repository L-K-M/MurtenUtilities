import Foundation
import MurtenCore
import ObtainintoshCore

/// The background check: for every tracked program that is installed, is a
/// newer release out? One finding per program, scoped by its entry id, for
/// `UpdateRule` to judge.
///
/// Reads only (`UpdateObserving`). Programs that are not installed cannot
/// have an update and cost no request. A program removed from the list is
/// reported as checked, so its suggestion resolves. Every failure is
/// reported against its program's scope, never as "nothing found".
public struct ObtainintoshWatcher: Watcher {
    /// Releases are rare, and unauthenticated GitHub allows 60 requests an hour.
    public static let interval: TimeInterval = 6 * 3600
    /// Room for a few dozen programs at two lookups at a time.
    public static let timeout: TimeInterval = 120
    static let concurrency = 2

    public let moduleID = UpdateFinding.moduleID
    public let cadence = WatchCadence(interval: ObtainintoshWatcher.interval, timeout: ObtainintoshWatcher.timeout,
                                      resources: .network)

    private let observer: UpdateObserving
    private let now: @Sendable () -> Date

    public init(observer: UpdateObserving, now: @escaping @Sendable () -> Date = { Date() }) {
        self.observer = observer
        self.now = now
    }

    public func observe() async -> Observation {
        let observedAt = now()
        let data: TrackedAppData?
        do {
            data = try observer.trackedList()
        } catch {
            return .unavailable(moduleID: moduleID, at: observedAt,
                                ObservationFailure(kind: .malformedResponse,
                                                   message: "The program list could not be read: \(error.localizedDescription)"))
        }
        guard let data else { return .complete(moduleID: moduleID, at: observedAt, scopes: []) }

        // Checked and gone: a removed program has no update to suggest.
        var completed = Set(data.removedAppIDs.map(UpdateFinding.scope(forAppID:)))
        let installed = await observer.installedVersions(of: data.apps)
        if Task.isCancelled { return cancelled(at: observedAt) }

        var candidates: [(app: TrackedApp, installed: InstalledVersion)] = []
        for (app, copy) in zip(data.apps, installed) {
            if let copy, !copy.version.isEmpty {
                candidates.append((app, copy))
            } else {
                completed.insert(UpdateFinding.scope(forAppID: app.id))
            }
        }

        let budget = GitHubRateBudget(maximumRequests: await observer.gitHubAllowance())
        let observer = self.observer
        let results = await boundedOrderedMap(candidates.map(\.app), limit: Self.concurrency) { app in
            if Task.isCancelled { return Result<Release, Error>.failure(CancellationError()) }
            do {
                return .success(try await observer.latestRelease(of: app, budget: budget))
            } catch {
                return .failure(error)
            }
        }
        if Task.isCancelled { return cancelled(at: observedAt) }

        var findings: [Finding] = []
        var failures: [ObservationFailure] = []
        for (candidate, result) in zip(candidates, results) {
            let scope = UpdateFinding.scope(forAppID: candidate.app.id)
            switch result {
            case .success(let release):
                completed.insert(scope)
                findings.append(UpdateFinding.make(app: candidate.app, installed: candidate.installed.version,
                                                   latest: release.version, at: observedAt))
            case .failure(let error as LookupFailure) where error.kind == .unsupported:
                // No client for this forge: nothing can be known, nothing to suggest.
                completed.insert(scope)
            case .failure(let error):
                failures.append(ObservationFailure(kind: Self.kind(of: error), scope: scope,
                                                   message: boundedCheckMessage("\(candidate.app.name): "
                                                       + error.localizedDescription)))
            }
        }
        return Observation(moduleID: moduleID, observedAt: observedAt, findings: findings,
                           completedScopes: completed, failures: failures)
    }

    private func cancelled(at date: Date) -> Observation {
        .unavailable(moduleID: moduleID, at: date, ObservationFailure(kind: .failed, message: "The check was stopped."))
    }

    static func kind(of error: Error) -> ObservationFailure.Kind {
        guard let failure = error as? LookupFailure else { return .failed }
        switch failure.kind {
        case .unreachable: return .unreachable
        case .malformedResponse: return .malformedResponse
        case .permissionDenied: return .permissionDenied
        case .rateLimited, .unsupported, .failed: return .failed
        }
    }
}
