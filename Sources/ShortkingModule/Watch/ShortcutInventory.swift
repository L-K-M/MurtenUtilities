import Foundation
import ShortkingCore
import ShortkingKit

/// How the watcher turns a saved inventory plus fresh system shortcuts into
/// conflicts, with the same merge and analysis a scan uses.
enum ShortcutInventory {

    static func includesSystemShortcuts(_ claims: [Claim]) -> Bool {
        claims.contains { $0.layer == .symbolic }
    }

    /// The saved inventory with its symbolic layer replaced by `system`.
    ///
    /// Everything at the symbolic layer goes, including the input-source
    /// enrichment the scan merged into it: what matters for a conflict is which
    /// combination each system shortcut sits on now, and the fresh read says.
    static func replacingSystemShortcuts(in saved: [Claim], with system: [Claim]) -> [Claim] {
        ClaimMerger.merge(saved.filter { $0.layer != .symbolic } + system)
    }

    /// Every conflict in `claims`, as the pane's Conflicts view lists them.
    static func conflicts(in claims: [Claim]) -> [Conflict] {
        ConflictAnalyzer.conflicts(in: ConflictAnalyzer.analyze(ClaimMerger.group(claims)))
    }
}
