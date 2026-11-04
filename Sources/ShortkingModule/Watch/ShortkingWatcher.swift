import Foundation
import MurtenCore
import ShortkingCore

/// Everything the watcher may read. Observation only: nothing here writes,
/// prompts, needs a privacy grant or spawns a process. The live
/// implementation is `LiveShortcutInventory`; tests pass fixtures.
protocol ShortcutInventoryObserving: Sendable {
    /// The inventory the pane saved after its last scan; nil when none exists.
    /// Throws `StoreFileReader.ReadError` for a file it cannot use.
    func savedInventory() throws -> [Claim]?

    /// macOS's system shortcuts as of now. Empty when they could not be read.
    func currentSystemShortcuts() async -> [Claim]

    /// `Conflict.acknowledgementSignature`s the user acknowledged in the pane.
    func acknowledgedConflicts() -> Set<String>
}

/// Shortking's background check: the last full inventory, with macOS's system
/// shortcuts read fresh, analysed for conflicts between apps.
///
/// A full scan is not a watcher's job. It needs Accessibility for menus, Input
/// Monitoring for taps, registers hotkeys to probe and can spawn hundreds of
/// `nm` processes; all of that stays in the pane. What changes most between
/// scans without the user opening Shortking is the system shortcuts they
/// reassign in System Settings, and reading those needs nothing.
struct ShortkingWatcher: Watcher {

    let moduleID = ShortkingSuite.moduleID
    let cadence = WatchCadence(interval: 60 * 60)

    private let inventory: any ShortcutInventoryObserving
    private let now: @Sendable () -> Date

    init(inventory: any ShortcutInventoryObserving, now: @escaping @Sendable () -> Date = { Date() }) {
        self.inventory = inventory
        self.now = now
    }

    func observe() async -> WatchObservation {
        let observedAt = now()

        let saved: [Claim]
        do {
            guard let claims = try inventory.savedInventory() else {
                return unavailable(at: observedAt, .toolMissing,
                                   "No shortcut inventory yet. Open Shortcut Detective once to take one.")
            }
            saved = claims
        } catch let error as StoreFileReader.ReadError {
            switch error {
            case .newerSchema:
                return unavailable(at: observedAt, .malformedResponse,
                                   "The saved shortcut inventory comes from a newer Shortcut Detective.")
            case .malformed:
                return unavailable(at: observedAt, .malformedResponse,
                                   "The saved shortcut inventory could not be read.")
            }
        } catch {
            return unavailable(at: observedAt, .failed,
                               "The saved shortcut inventory could not be opened: \(error.localizedDescription)")
        }
        guard !Task.isCancelled else { return cancelled(at: observedAt) }

        // System shortcuts are refreshed only when the inventory has them: a
        // user who left them out of the scan does not get them from the watch.
        var claims = saved
        var failures: [ObservationFailure] = []
        if ShortcutInventory.includesSystemShortcuts(saved) {
            let system = await inventory.currentSystemShortcuts()
            guard !Task.isCancelled else { return cancelled(at: observedAt) }

            // A Mac always has system shortcuts, so none means the read failed.
            // The last inventory still stands, but cannot prove anything resolved.
            if system.isEmpty {
                failures.append(ObservationFailure(
                    kind: .failed,
                    message: "macOS's system shortcuts could not be read; using the last inventory."))
            } else {
                claims = ShortcutInventory.replacingSystemShortcuts(in: saved, with: system)
            }
        }

        let findings = ShortcutConflictFinding.findings(
            for: ShortcutInventory.conflicts(in: claims),
            acknowledged: inventory.acknowledgedConflicts(),
            at: observedAt)

        return WatchObservation(moduleID: moduleID, observedAt: observedAt, findings: findings,
                                completedScopes: failures.isEmpty ? [.local] : [], failures: failures)
    }

    private func unavailable(at date: Date, _ kind: ObservationFailure.Kind, _ message: String) -> WatchObservation {
        .unavailable(moduleID: moduleID, at: date, ObservationFailure(kind: kind, message: message))
    }

    private func cancelled(at date: Date) -> WatchObservation {
        unavailable(at: date, .failed, "The check was cancelled.")
    }
}
