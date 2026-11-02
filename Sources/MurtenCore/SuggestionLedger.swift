import Foundation

/// How long the ledger remembers things, so the persisted file stays small.
public struct RetentionPolicy: Equatable, Sendable {
    /// Resolved episodes are kept this long, then forgotten.
    public let resolvedRetention: TimeInterval
    /// Hard cap on records; resolved ones go first, oldest first.
    public let maximumRecords: Int

    public init(resolvedRetention: TimeInterval, maximumRecords: Int) {
        self.resolvedRetention = resolvedRetention
        self.maximumRecords = maximumRecords
    }

    public static let standard = RetentionPolicy(resolvedRetention: 30 * 24 * 3600, maximumRecords: 256)
}

/// Bounds notification delivery, never collection: findings are always
/// recorded; at most `maximum` notifications go out per `window`.
public struct NotificationThrottle: Equatable, Sendable {
    public let maximum: Int
    public let window: TimeInterval

    public init(maximum: Int, window: TimeInterval) {
        self.maximum = maximum
        self.window = window
    }

    public static let standard = NotificationThrottle(maximum: 3, window: 3600)

    public func admits(after deliveries: [Date], at now: Date) -> Bool {
        deliveries.filter { now.timeIntervalSince($0) < window }.count < maximum
    }
}

/// The suggestion lifecycle as a pure value: episodes, dedupe, snooze,
/// dismissal, staleness and watcher health. `SuggestionStore` owns one and
/// persists it; everything here is testable without a clock or a disk.
///
///     absent ──finding over threshold──▶ active (episode n) ──complete check without it──▶ resolved
///        ▲                                │  ▲                                                 │
///        │                     check fails│  │next successful check                            │
///        │                                ▼  │                                                 │
///        │                              active + stale                                         │
///        └──────────────── recurrence opens episode n + 1 ◀────────────────────────────────────┘
///
/// Value changes inside an episode refresh it; they never open a new one.
public struct SuggestionLedger: Codable, Equatable, Sendable {

    public struct Record: Codable, Equatable, Sendable {
        public enum Phase: Codable, Equatable, Sendable {
            case active
            case resolved(at: Date)
        }

        public var key: SuggestionKey
        public var content: SuggestionContent
        public var episode: Int
        public var phase: Phase
        public var episodeStartedAt: Date
        public var lastObservedAt: Date
        /// Set when a check of this scope failed after the last confirmation.
        public var staleSince: Date?
        /// Survives refreshes, resolution and restarts until the deadline.
        public var snoozedUntil: Date?
        /// Dismissal hides only this episode; a recurrence is shown again.
        public var dismissedEpisode: Int?
        /// Prevents a second notification for the same episode, including
        /// after a restart.
        public var notifiedEpisode: Int?

        public var isActive: Bool { phase == .active }
    }

    /// Last success and last failure are kept separately: a failing check
    /// must not read as healthy, and an old failure must not hide a recovery.
    public struct WatchHealth: Codable, Equatable, Sendable {
        public var lastSuccessAt: Date?
        public var lastFailureAt: Date?
        public var lastFailure: ObservationFailure?
    }

    public enum Event: Hashable, Sendable {
        case opened(SuggestionKey)
        case refreshed(SuggestionKey)
        case resolved(SuggestionKey)
        case becameStale(SuggestionKey)
    }

    public private(set) var records: [SuggestionKey: Record] = [:]
    public private(set) var health: [String: WatchHealth] = [:]
    public private(set) var notificationDeliveries: [Date] = []

    public init() {}

    // MARK: - Observations

    /// Folds one observation into the ledger and reports what changed.
    @discardableResult
    public mutating func apply(_ observation: WatchObservation, rule: any SuggestionRule) -> [Event] {
        let moduleID = observation.moduleID
        recordHealth(of: observation)

        var events: [Event] = []
        var reported = Set<SuggestionKey>()

        // A watcher may only report for its own module.
        for finding in observation.findings where finding.moduleID == moduleID {
            reported.insert(finding.key)
            if let event = fold(finding, rule: rule) { events.append(event) }
        }

        // Checked and absent: the condition is gone.
        for key in activeKeys(in: moduleID) where !reported.contains(key)
            && observation.completedScopes.contains(key.scope) {
            resolve(key, at: observation.observedAt)
            events.append(.resolved(key))
        }

        // Could not check: keep the suggestion, flag it as possibly outdated.
        let wholeCheckFailed = observation.failures.contains { $0.scope == nil }
        let failedScopes = Set(observation.failures.compactMap(\.scope))

        // The watcher listed every scope that exists: the rest are gone.
        if observation.coverage == .exhaustive, !wholeCheckFailed {
            // A finding proves its scope exists even if the watcher left the
            // scope out of completedScopes.
            let ownFindings = observation.findings.filter { $0.moduleID == moduleID }
            let existing = observation.completedScopes.union(failedScopes)
                .union(ownFindings.map(\.scope))
            for key in activeKeys(in: moduleID) where !reported.contains(key) && !existing.contains(key.scope) {
                resolve(key, at: observation.observedAt)
                events.append(.resolved(key))
            }
        }

        for key in activeKeys(in: moduleID) where !reported.contains(key)
            && (wholeCheckFailed || failedScopes.contains(key.scope))
            && records[key]?.staleSince == nil {
            records[key]?.staleSince = observation.observedAt
            events.append(.becameStale(key))
        }

        return events
    }

    private mutating func fold(_ finding: Finding, rule: any SuggestionRule) -> Event? {
        let key = finding.key
        let existing = records[key]
        let state: RuleState = existing?.isActive == true ? .active : .inactive

        guard let content = rule.suggestion(for: finding, state: state) else {
            guard existing?.isActive == true else { return nil }
            resolve(key, at: finding.observedAt)
            return .resolved(key)
        }

        if var record = existing, record.isActive {
            record.content = content
            record.lastObservedAt = finding.observedAt
            record.staleSince = nil
            records[key] = record
            return .refreshed(key)
        }

        records[key] = Record(
            key: key, content: content, episode: (existing?.episode ?? 0) + 1, phase: .active,
            episodeStartedAt: finding.observedAt, lastObservedAt: finding.observedAt,
            staleSince: nil, snoozedUntil: existing?.snoozedUntil,
            dismissedEpisode: existing?.dismissedEpisode, notifiedEpisode: existing?.notifiedEpisode)
        return .opened(key)
    }

    private mutating func recordHealth(of observation: WatchObservation) {
        var entry = health[observation.moduleID] ?? WatchHealth()
        if observation.outcome != .unavailable { entry.lastSuccessAt = observation.observedAt }
        if let failure = observation.failures.first {
            entry.lastFailureAt = observation.observedAt
            entry.lastFailure = failure
        }
        health[observation.moduleID] = entry
    }

    private mutating func resolve(_ key: SuggestionKey, at date: Date) {
        records[key]?.phase = .resolved(at: date)
        records[key]?.staleSince = nil
    }

    private func activeKeys(in moduleID: String) -> [SuggestionKey] {
        records.values.filter { $0.key.moduleID == moduleID && $0.isActive }.map(\.key)
    }

    // MARK: - User actions

    /// Hides the suggestion until `date`; returns false for an unknown key.
    @discardableResult
    public mutating func snooze(_ key: SuggestionKey, until date: Date) -> Bool {
        guard records[key] != nil else { return false }
        records[key]?.snoozedUntil = date
        return true
    }

    /// Hides the current episode; returns false unless the key is active.
    @discardableResult
    public mutating func dismiss(_ key: SuggestionKey) -> Bool {
        guard let record = records[key], record.isActive else { return false }
        records[key]?.dismissedEpisode = record.episode
        return true
    }

    // MARK: - Surfaces

    /// Active suggestions that are neither snoozed nor dismissed, newest
    /// episode first.
    public func suggestions(at now: Date) -> [Suggestion] {
        records.values
            .filter { isVisible($0, at: now) }
            .map { record in
                Suggestion(key: record.key, content: record.content,
                           episodeStartedAt: record.episodeStartedAt,
                           lastObservedAt: record.lastObservedAt,
                           freshness: record.staleSince.map { .stale(since: $0) } ?? .current)
            }
            .sorted { lhs, rhs in
                if lhs.episodeStartedAt != rhs.episodeStartedAt { return lhs.episodeStartedAt > rhs.episodeStartedAt }
                return lhs.key.description < rhs.key.description
            }
    }

    private func isVisible(_ record: Record, at now: Date) -> Bool {
        guard record.isActive, record.dismissedEpisode != record.episode else { return false }
        guard let snoozedUntil = record.snoozedUntil else { return true }
        return snoozedUntil <= now
    }

    /// Claims the notification for a newly opened episode. True at most once
    /// per episode, only while visible, and only within the throttle.
    public mutating func claimNotification(for key: SuggestionKey, at now: Date,
                                           throttle: NotificationThrottle) -> Bool {
        guard let record = records[key], isVisible(record, at: now),
              record.notifiedEpisode != record.episode,
              throttle.admits(after: notificationDeliveries, at: now) else { return false }

        records[key]?.notifiedEpisode = record.episode
        notificationDeliveries.append(now)
        return true
    }

    // MARK: - Retention

    /// Forgets old resolved episodes, expired snoozes, modules no longer in
    /// the roster and deliveries outside the throttle window.
    public mutating func prune(at now: Date, policy: RetentionPolicy, throttle: NotificationThrottle,
                               knownModules: Set<String>) {
        records = records.filter { key, record in
            guard knownModules.contains(key.moduleID) else { return false }
            guard case .resolved(let resolvedAt) = record.phase else { return true }
            return now.timeIntervalSince(resolvedAt) < policy.resolvedRetention
        }

        for (key, record) in records {
            if let until = record.snoozedUntil, until <= now { records[key]?.snoozedUntil = nil }
        }

        if records.count > policy.maximumRecords {
            let evictionOrder = records.values.sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive { return !lhs.isActive }
                return lhs.lastObservedAt < rhs.lastObservedAt
            }
            for record in evictionOrder.prefix(records.count - policy.maximumRecords) {
                records[record.key] = nil
            }
        }

        health = health.filter { knownModules.contains($0.key) }
        notificationDeliveries = notificationDeliveries.filter { now.timeIntervalSince($0) < throttle.window }
    }

    // MARK: - Codable

    // Records persist as an array; a dictionary keyed by a struct would
    // encode as an unreadable flat key/value list.
    private enum CodingKeys: String, CodingKey {
        case records, health, notificationDeliveries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let list = try container.decode([Record].self, forKey: .records)
        records = Dictionary(list.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
        health = try container.decodeIfPresent([String: WatchHealth].self, forKey: .health) ?? [:]
        notificationDeliveries = try container.decodeIfPresent([Date].self, forKey: .notificationDeliveries) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(records.values.sorted { $0.key.description < $1.key.description }, forKey: .records)
        try container.encode(health, forKey: .health)
        try container.encode(notificationDeliveries, forKey: .notificationDeliveries)
    }
}
