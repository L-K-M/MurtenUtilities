import Foundation

/// Dedupe identity of a suggestion: module, condition and scope. A repeated
/// finding refreshes the suggestion with this key instead of stacking.
/// Rendered as "<module>.<condition>@<scope>", e.g.
/// "dockvac.reclaimable@unix:///var/run/docker.sock".
public struct SuggestionKey: Hashable, Codable, Sendable, CustomStringConvertible {
    public let moduleID: String
    public let condition: String
    public let scope: FindingScope

    public init(moduleID: String, condition: String, scope: FindingScope = .local) {
        self.moduleID = moduleID
        self.condition = condition
        self.scope = scope
    }

    public var description: String { "\(moduleID).\(condition)@\(scope.rawValue)" }
}

/// A recommendation that an on-demand tool should run, as the surfaces show
/// it. A suggestion never repairs anything on its own: clicking it only opens
/// the owning module's pane (see docs/architecture.md).
public struct Suggestion: Identifiable, Hashable, Sendable {
    public enum Freshness: Hashable, Sendable {
        /// Confirmed by the most recent check of its scope.
        case current
        /// The last check of its scope failed; the finding may be outdated.
        case stale(since: Date)
    }

    public let key: SuggestionKey
    public let content: SuggestionContent
    /// When the current episode started: the condition was first observed
    /// after being absent or resolved.
    public let episodeStartedAt: Date
    public let lastObservedAt: Date
    public let freshness: Freshness

    public init(key: SuggestionKey, content: SuggestionContent, episodeStartedAt: Date,
                lastObservedAt: Date, freshness: Freshness) {
        self.key = key
        self.content = content
        self.episodeStartedAt = episodeStartedAt
        self.lastObservedAt = lastObservedAt
        self.freshness = freshness
    }

    public var id: SuggestionKey { key }
    public var moduleID: String { key.moduleID }
    public var title: String { content.title }
    public var detail: String { content.detail }
    public var route: ModuleRoute { content.route }
}
