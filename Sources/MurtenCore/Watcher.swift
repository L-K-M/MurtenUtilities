import Foundation

/// Resources a watcher consumes, so the coordinator can pause it under the
/// user's budget (metered network, battery).
public struct WatchResources: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Talks to a remote host (GitHub, Forgejo, an SSH Docker endpoint).
    public static let network = WatchResources(rawValue: 1 << 0)
}

/// How often a watcher runs and how long one poll may take.
public struct WatchCadence: Hashable, Sendable {
    /// Floor for every watcher: background checks stay rare.
    public static let minimumInterval: TimeInterval = 15 * 60
    public static let defaultTimeout: TimeInterval = 60

    public let interval: TimeInterval
    public let timeout: TimeInterval
    public let resources: WatchResources

    public init(interval: TimeInterval, timeout: TimeInterval = WatchCadence.defaultTimeout,
                resources: WatchResources = []) {
        self.interval = max(interval, Self.minimumInterval)
        self.timeout = timeout
        self.resources = resources
    }
}

/// Periodic, unprivileged observation feeding the suggestion feed. A watcher
/// only ever *notices*: it must not need privilege or a new privacy grant to
/// look, never prompts, and never repairs. One watcher per module.
public protocol Watcher: Sendable {
    /// The module this watcher feeds.
    var moduleID: String { get }
    var cadence: WatchCadence { get }
    /// One cheap check. Never throws: a failed or partial check is reported
    /// in the observation, because "could not look" is not "nothing found".
    /// Must honor task cancellation; a disabled watcher's work is cancelled.
    func observe() async -> Observation
}

/// A module's watcher with the rule that turns its findings into suggestions.
/// Observation and judgment stay separate types so a rule can be tested
/// against fixture findings without running any I/O.
public struct WatcherRegistration: Sendable {
    public let watcher: any Watcher
    public let rule: any SuggestionRule

    public init(watcher: any Watcher, rule: any SuggestionRule) {
        self.watcher = watcher
        self.rule = rule
    }

    public var moduleID: String { watcher.moduleID }
}
