import Foundation
import MurtenCore

/// Turns the conflicts a watch found into findings, one per shortcut.
///
/// Each shortcut is its own condition (`conflict:<groupingKey>`) on the local
/// scope, so a completed check that no longer sees a conflict resolves exactly
/// that suggestion. The acknowledgement is evidence rather than a filter: the
/// rule decides, and an acknowledged conflict resolves its suggestion.
public enum ShortcutConflictFinding {

    public static let conditionPrefix = "conflict:"

    /// Evidence keys the watcher writes and `ShortcutConflictRule` reads.
    public enum EvidenceKey {
        /// The shortcut as displayed, e.g. "⌘⇧Space".
        public static let combo = "combo"
        /// `KeyCombo.groupingKey`, for the route.
        public static let comboKey = "comboKey"
        /// The contenders' names as one phrase, e.g. "Raycast and Spotlight".
        public static let contenders = "contenders"
        /// How many distinct owners are fighting.
        public static let contenderCount = "contenderCount"
        /// 1 when the user acknowledged this exact conflict in the pane, else 0.
        public static let acknowledged = "acknowledged"
    }

    public static func condition(comboKey: String) -> String {
        conditionPrefix + comboKey
    }

    /// One finding per conflict between apps. `acknowledged` holds
    /// `Conflict.acknowledgementSignature` values.
    public static func findings(for conflicts: [Conflict], acknowledged: Set<String>,
                                at date: Date) -> [Finding] {
        conflicts.filter(\.isBetweenApps).map { conflict in
            let names = conflict.contenderNames
            return Finding(
                moduleID: ShortkingSuite.moduleID,
                condition: condition(comboKey: conflict.combo.groupingKey),
                observedAt: date,
                evidence: [
                    EvidenceKey.combo: .text(conflict.combo.displayString),
                    EvidenceKey.comboKey: .text(conflict.combo.groupingKey),
                    EvidenceKey.contenders: .text(phrase(names)),
                    EvidenceKey.contenderCount: .count(names.count),
                    EvidenceKey.acknowledged: .count(
                        acknowledged.contains(conflict.acknowledgementSignature) ? 1 : 0),
                ]
            )
        }
    }

    /// "A", "A and B", "A, B and C".
    static func phrase(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }
}
