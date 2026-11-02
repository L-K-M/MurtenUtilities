import Foundation

/// Whether the finding's key currently has an active suggestion. Rules use it
/// for hysteresis: activate at ≥ 4 GB, stay active until < 3 GB, so a value
/// hovering at the threshold does not open and close episodes.
public enum RuleState: Sendable {
    case inactive
    case active
}

/// What the user reads and where clicking takes them.
public struct SuggestionContent: Hashable, Codable, Sendable {
    /// Short headline, e.g. "Docker is holding ~8 GB".
    public let title: String
    /// One or two sentences of context plus what clicking through would do.
    public let detail: String
    /// The pane, action and context the suggestion opens. Opening never
    /// authorizes a repair; the pane re-scans and asks.
    public let route: ModuleRoute

    public init(title: String, detail: String, route: ModuleRoute) {
        self.title = title
        self.detail = detail
        self.route = route
    }
}

/// A module's threshold: turns a finding into at most one suggestion. Rules
/// are pure; thresholds live with the module, not the suggestion engine.
public protocol SuggestionRule: Sendable {
    /// The suggestion this finding warrants, or nil when it is below threshold.
    /// Returning nil for a key that is active resolves its episode.
    func suggestion(for finding: Finding, state: RuleState) -> SuggestionContent?
}
