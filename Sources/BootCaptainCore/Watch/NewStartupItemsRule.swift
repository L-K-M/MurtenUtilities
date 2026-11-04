import Foundation
import MurtenCore

/// Identifiers the background check, its rule and the pane share.
public enum StartupWatch {
    public static let moduleID = "bootcaptain"
    /// Route action that opens the pane on the items not yet reviewed.
    public static let reviewAction = "review"
    /// One condition per product, e.g. "new-startup-items:app:com.docker.docker".
    /// The scope stays `.local` (this Mac), so a complete check resolves
    /// every product it no longer reports, including uninstalled ones.
    public static let conditionPrefix = "new-startup-items:"
    /// Labels named in a suggestion's detail; the pane lists the rest.
    static let namedLabelLimit = 3

    /// The finding for one product's new items.
    public static func finding(for group: NewStartupItems, at date: Date) -> Finding {
        let labels = group.items.map(\.label)
        var named = labels.prefix(namedLabelLimit).joined(separator: ", ")
        if labels.count > namedLabelLimit {
            named += " and \(labels.count - namedLabelLimit) more"
        }
        return Finding(
            moduleID: moduleID, condition: conditionPrefix + group.product.key, scope: .local,
            observedAt: date,
            evidence: [
                "count": .count(group.items.count),
                "product": .text(group.product.name),
                "labels": .text(named),
            ])
    }
}

/// Any startup item the user has not reviewed is worth a suggestion: one per
/// product, opening the pane on the unreviewed list. Counts may change inside
/// an episode (a third agent appears); that refreshes the suggestion rather
/// than opening a new one. Marking the list as reviewed in the pane resolves
/// it on the next check.
public struct NewStartupItemsRule: SuggestionRule {
    public init() {}

    public func suggestion(for finding: Finding, state: RuleState) -> SuggestionContent? {
        guard finding.moduleID == StartupWatch.moduleID,
              finding.condition.hasPrefix(StartupWatch.conditionPrefix),
              let count = finding.count("count"), count > 0 else { return nil }

        let product = finding.text("product").flatMap { $0.isEmpty ? nil : $0 } ?? "An app"
        let title = "\(product) installed \(count) new startup item\(count == 1 ? "" : "s")"

        var detail = count == 1
            ? "It is not in the list you last reviewed in Startup Manager"
            : "They are not in the list you last reviewed in Startup Manager"
        if let labels = finding.text("labels"), !labels.isEmpty {
            detail += ": \(labels)"
        }
        detail += ". Open Startup Manager to see what \(count == 1 ? "it runs" : "they run"); nothing changes until you choose to."

        return SuggestionContent(
            title: title, detail: detail,
            route: ModuleRoute(moduleID: StartupWatch.moduleID, action: StartupWatch.reviewAction))
    }
}
