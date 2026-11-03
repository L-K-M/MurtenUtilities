import Foundation
import MurtenCore

/// A conflict between apps that the user has not acknowledged in the pane
/// becomes a suggestion: "⌘⇧Space is claimed by two apps".
///
/// A conflict is there or it is not, so the rule needs no hysteresis. Clicking
/// the suggestion opens the Conflicts view at that shortcut; nothing is
/// rebound or selected for an action.
public struct ShortcutConflictRule: SuggestionRule {

    public init() {}

    public func suggestion(for finding: Finding, state: RuleState) -> SuggestionContent? {
        typealias Key = ShortcutConflictFinding.EvidenceKey

        guard finding.condition.hasPrefix(ShortcutConflictFinding.conditionPrefix),
              finding.count(Key.acknowledged) != 1,
              let combo = finding.text(Key.combo),
              let comboKey = finding.text(Key.comboKey)
        else { return nil }

        let count = finding.count(Key.contenderCount) ?? 0
        let contenders = finding.text(Key.contenders) ?? ""

        return SuggestionContent(
            title: Self.title(combo: combo, contenderCount: count, contenders: contenders),
            detail: Self.detail(combo: combo, contenderCount: count, contenders: contenders),
            route: ShortkingSuite.conflictRoute(comboKey: comboKey)
        )
    }

    // MARK: - Wording

    static func title(combo: String, contenderCount: Int, contenders: String) -> String {
        guard contenderCount > 1 else {
            return contenders.isEmpty
                ? "\(combo) is claimed more than once"
                : "\(combo) is claimed more than once by \(contenders)"
        }
        return "\(combo) is claimed by \(spelledOut(contenderCount)) apps"
    }

    static func detail(combo: String, contenderCount: Int, contenders: String) -> String {
        let action = "Open Shortking to see which one wins and where to change the others."
        switch contenderCount {
        case ...1:
            let owner = contenders.isEmpty ? "One app" : contenders
            return "\(owner) binds \(combo) to more than one command, and only one of them runs. "
                + action
        case 2:
            return "\(contenders) both claim \(combo), and only one of them gets it. " + action
        default:
            return "\(contenders) all claim \(combo), and only one of them gets it. " + action
        }
    }

    private static let numberWords = ["two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]

    /// "two" through "ten", digits beyond.
    static func spelledOut(_ number: Int) -> String {
        let index = number - 2
        return numberWords.indices.contains(index) ? numberWords[index] : "\(number)"
    }
}
