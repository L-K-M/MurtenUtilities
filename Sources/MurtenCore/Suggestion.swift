import Foundation

/// A recommendation that an on-demand tool should run, distilled from a
/// `Watcher`'s finding. Deduplicated by `key`, snoozable, and always resolves
/// to a deep link into the owning module — a suggestion never repairs anything
/// on its own (see docs/architecture.md).
public struct Suggestion: Identifiable, Equatable, Sendable {
    /// Stable dedupe identity, conventionally "<module>.<finding kind>" — a
    /// repeated finding refreshes the existing suggestion instead of stacking.
    public let key: String
    /// The module the suggestion deep-links into.
    public let moduleID: String
    /// Short headline, e.g. "Docker is holding ~8 GB".
    public let title: String
    /// One or two sentences of context plus what clicking through would do.
    public let detail: String

    public init(key: String, moduleID: String, title: String, detail: String) {
        self.key = key
        self.moduleID = moduleID
        self.title = title
        self.detail = detail
    }

    public var id: String { key }
}

/// Periodic, unprivileged observation feeding the suggestion feed. A watcher
/// only ever *notices* — it must not need privileges merely to look, and it
/// never repairs. Remediation stays in the module, behind explicit user action.
public protocol Watcher: Sendable {
    /// The module this watcher feeds.
    var moduleID: String { get }
    /// One cheap check. Return nil when nothing is worth reporting; never
    /// throw for "nothing found" — only for a failed observation.
    func poll() async throws -> Suggestion?
}
