import Foundation
import MurtenCore
import BootCaptainCore

/// BootCaptain's background check: compares the launchd plists a standard
/// user can read with the inventory the user last reviewed in the pane, and
/// reports new items per product ("Docker installed 2 new startup items").
/// It only reads: the folders through `StartupInventoryObserving`, the
/// reviewed inventory through `ReviewedInventoryReading`.
public struct StartupItemsWatcher: Watcher {
    /// Startup items change when software is installed; hourly is plenty.
    public static let defaultCadence = WatchCadence(interval: 60 * 60)

    public let moduleID = StartupWatch.moduleID
    public let cadence: WatchCadence

    private let inventory: any StartupInventoryObserving
    private let reviewed: any ReviewedInventoryReading
    private let now: @Sendable () -> Date

    public init(inventory: any StartupInventoryObserving, reviewed: any ReviewedInventoryReading,
                cadence: WatchCadence = StartupItemsWatcher.defaultCadence,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.inventory = inventory
        self.reviewed = reviewed
        self.cadence = cadence
        self.now = now
    }

    public func observe() async -> WatchObservation {
        let baseline: ReviewedInventory
        switch reviewed.reviewedInventory() {
        case .notYetReviewed:
            return .unavailable(moduleID: moduleID, at: now(), ObservationFailure(
                kind: .toolMissing,
                message: "Open Startup Manager once so it knows which startup items you have already seen."))
        case .unreadable:
            return .unavailable(moduleID: moduleID, at: now(), ObservationFailure(
                kind: .malformedResponse,
                message: "The list of reviewed startup items could not be read. Open Startup Manager and mark the list as reviewed."))
        case .reviewed(let inventory):
            baseline = inventory
        }

        let snapshot = await inventory.observeInventory()
        let observedAt = now()
        let findings = StartupInventoryDiff
            .newItemsByProduct(current: snapshot.items, reviewed: baseline, installedApps: snapshot.installedApps)
            .map { StartupWatch.finding(for: $0, at: observedAt) }

        guard !snapshot.failures.isEmpty else {
            return .complete(moduleID: moduleID, at: observedAt, findings: findings)
        }

        // Whatever was found is real, but an incomplete read never resolves
        // a product: the scope is not reported as completed.
        let failures = snapshot.failures.map { failure in
            switch failure.kind {
            case .cancelled:
                return ObservationFailure(kind: .timedOut, scope: .local, message: failure.reason)
            case .unreadable:
                return ObservationFailure(kind: .permissionDenied, scope: .local,
                                          message: "Could not read \(failure.path): \(failure.reason)")
            }
        }
        return WatchObservation(moduleID: moduleID, observedAt: observedAt, findings: findings,
                                completedScopes: [], failures: failures)
    }
}
