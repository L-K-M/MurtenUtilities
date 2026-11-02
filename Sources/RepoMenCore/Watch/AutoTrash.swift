import Foundation

/// One line of the auto-trash log the pane shows: what an armed pass moved to the
/// Trash, or why it left an item alone.
package struct AutoTrashLogEntry: Identifiable, Hashable, Codable, Sendable {
    package enum Result: Hashable, Codable, Sendable {
        case trashed
        case skipped(reason: String)
    }

    package let id: UUID
    package let date: Date
    package let path: String
    package let label: String
    package let bytes: Int64
    package let result: Result

    package init(id: UUID = UUID(), date: Date, path: String, label: String, bytes: Int64, result: Result) {
        self.id = id
        self.date = date
        self.path = path
        self.label = label
        self.bytes = bytes
        self.result = result
    }
}

/// The pure decisions behind armed auto-trash (PLAN.md, *User-armed
/// automation*): which folders may run, which items go, when the next pass is
/// due, and how the log is kept. `AutoTrashController` does the IO.
package enum AutoTrash {
    /// The standalone app's watch interval.
    package static let interval: TimeInterval = 6 * 3600
    /// Settle time before the first pass after launch or arming.
    package static let initialDelay: TimeInterval = 30
    /// How soon to look again while background work is not allowed. Only a
    /// settings check; nothing is scanned.
    package static let pausedRetry: TimeInterval = 15 * 60
    /// Entries kept in the log, newest first.
    package static let logLimit = 500

    /// Armed, enabled folders that background work may read. A folder in a
    /// privacy-protected location stays out even if armed: an unattended pass
    /// must not raise a prompt.
    package static func runnableFolders(_ folders: [WatchedFolder],
                                        protectedRoots: [String],
                                        readLink: (String) -> String? = ProtectedLocations.liveReadLink)
        -> [WatchedFolder] {
        folders.filter {
            $0.isEnabled && $0.autoTrashArmed
                && ProtectedLocations.classify($0.path, roots: protectedRoots, readLink: readLink) == .allowed
        }
    }

    /// The items an armed pass trashes: stale items governed by an armed folder.
    /// An unarmed folder nested in an armed one keeps its items, because the
    /// deepest watched folder governs (`WatchEngine.governingFolder`).
    package static func candidates(staleByRoot: [String: [CleanableItem]],
                                   armedPaths: Set<String>) -> [CleanableItem] {
        staleByRoot
            .filter { armedPaths.contains($0.key) }
            .flatMap(\.value)
            .sorted { $0.path < $1.path }
    }

    /// When the next pass may start: not before `earliest`, and not sooner than
    /// one interval after the last pass.
    package static func nextRun(lastRun: Date?, earliest: Date) -> Date {
        guard let lastRun else { return earliest }
        return max(earliest, lastRun.addingTimeInterval(interval))
    }

    /// Log lines for one pass's outcomes.
    package static func entries(for outcomes: [Reclaimer.Outcome], at date: Date) -> [AutoTrashLogEntry] {
        outcomes.map { outcome in
            AutoTrashLogEntry(date: date, path: outcome.item.path, label: outcome.item.label,
                              bytes: outcome.item.sizeBytes,
                              result: outcome.failure.map { .skipped(reason: $0) } ?? .trashed)
        }
    }

    /// Newest first, capped at `limit`.
    package static func appending(_ entries: [AutoTrashLogEntry], to log: [AutoTrashLogEntry],
                                  limit: Int = logLimit) -> [AutoTrashLogEntry] {
        Array((entries.sorted { $0.date > $1.date } + log).prefix(limit))
    }

    /// The run record a pass leaves for the menu section and Settings.
    package static func record(candidates: [CleanableItem], outcomes: [Reclaimer.Outcome],
                               at date: Date) -> WatchRunRecord {
        let reclaimed = outcomes.filter { $0.failure == nil }
        return WatchRunRecord(
            date: date, dryRun: false,
            candidateCount: candidates.count,
            candidateBytes: candidates.reduce(0) { $0 + $1.sizeBytes },
            reclaimedCount: reclaimed.count,
            reclaimedBytes: reclaimed.reduce(0) { $0 + $1.item.sizeBytes },
            failureCount: outcomes.count - reclaimed.count)
    }
}
