import Foundation

/// One directory RepoMen watches: the suite's background check reports build
/// artifacts under `path` whose newest content is older than `maxIdleDays`, and,
/// once the user arms it for this folder, auto-trash moves them to the Trash
/// (re-verified at trash time like any manual reclaim — see `AutoTrashController`
/// and `Reclaimer`).
package struct WatchedFolder: Identifiable, Hashable, Codable, Sendable {
    package let path: String
    /// Days since the artifact was last built before watch mode considers it stale.
    package var maxIdleDays: Int
    package var isEnabled: Bool
    /// The user armed auto-trash for this folder. Off by default and never
    /// inferred: the standalone app's global `watchAutoTrash` switch is not
    /// carried over, so folders saved by it decode unarmed.
    package var autoTrashArmed: Bool

    package var id: String { path }

    package init(path: String, maxIdleDays: Int = 30, isEnabled: Bool = true,
                 autoTrashArmed: Bool = false) {
        self.path = path
        self.maxIdleDays = maxIdleDays
        self.isEnabled = isEnabled
        self.autoTrashArmed = autoTrashArmed
    }

    private enum CodingKeys: String, CodingKey {
        case path, maxIdleDays, isEnabled, autoTrashArmed
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        maxIdleDays = try container.decode(Int.self, forKey: .maxIdleDays)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        autoTrashArmed = try container.decodeIfPresent(Bool.self, forKey: .autoTrashArmed) ?? false
    }
}

/// The persisted outcome of one auto-trash pass, shown in the menu section and in
/// Settings → Watch ("last run: repossessed 2.3 GB, 3 h ago").
package struct WatchRunRecord: Hashable, Codable, Sendable {
    package let date: Date
    /// True when the standalone app's report-only check wrote it. Auto-trash
    /// passes in the suite always reclaim; reports come from the background check.
    package let dryRun: Bool
    package let candidateCount: Int
    package let candidateBytes: Int64
    package let reclaimedCount: Int
    package let reclaimedBytes: Int64
    package let failureCount: Int

    package init(date: Date, dryRun: Bool, candidateCount: Int, candidateBytes: Int64,
                 reclaimedCount: Int, reclaimedBytes: Int64, failureCount: Int) {
        self.date = date
        self.dryRun = dryRun
        self.candidateCount = candidateCount
        self.candidateBytes = candidateBytes
        self.reclaimedCount = reclaimedCount
        self.reclaimedBytes = reclaimedBytes
        self.failureCount = failureCount
    }
}
