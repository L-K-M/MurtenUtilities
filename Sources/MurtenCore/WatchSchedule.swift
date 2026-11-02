import Foundation

/// When each watcher is due, as a pure value. `WatchCoordinator` drives it;
/// tests drive it with plain dates.
///
///     register ──initialDelay──▶ due ──start──▶ in flight ──success──▶ due after interval
///                                                     └──failure──▶ due after interval × 2ⁿ⁻¹ (capped)
public struct WatchSchedule: Sendable {
    /// Let launch settle before the first poll.
    public static let initialDelay: TimeInterval = 60
    /// After sleep, overdue checks wait this long for the network and disks.
    public static let wakeSettleDelay: TimeInterval = 60
    /// A paused poll asks the gate again after at most this long.
    public static let pauseRecheckInterval: TimeInterval = 15 * 60
    /// Longest back-off after repeated failures.
    public static let maximumBackoff: TimeInterval = 6 * 3600

    public enum Completion: Sendable {
        case succeeded
        case failed
    }

    public struct Entry: Equatable, Sendable {
        public let interval: TimeInterval
        public var nextDue: Date
        public var consecutiveFailures = 0
        public var inFlight = false
    }

    public private(set) var entries: [String: Entry] = [:]

    public init() {}

    public mutating func register(_ moduleID: String, interval: TimeInterval, at now: Date) {
        guard entries[moduleID] == nil else { return }
        entries[moduleID] = Entry(interval: interval, nextDue: now.addingTimeInterval(Self.initialDelay))
    }

    public mutating func unregister(_ moduleID: String) {
        entries[moduleID] = nil
    }

    /// Due modules not already polling, most overdue first.
    public func dueModules(at now: Date) -> [String] {
        entries.filter { !$0.value.inFlight && $0.value.nextDue <= now }
            .sorted { lhs, rhs in
                lhs.value.nextDue == rhs.value.nextDue ? lhs.key < rhs.key : lhs.value.nextDue < rhs.value.nextDue
            }
            .map(\.key)
    }

    /// The earliest moment something becomes due, nil when nothing waits.
    public func nextDeadline() -> Date? {
        entries.values.filter { !$0.inFlight }.map(\.nextDue).min()
    }

    public mutating func markStarted(_ moduleID: String) {
        entries[moduleID]?.inFlight = true
    }

    public mutating func markFinished(_ moduleID: String, _ completion: Completion, at now: Date) {
        guard var entry = entries[moduleID] else { return }
        entry.inFlight = false

        switch completion {
        case .succeeded:
            entry.consecutiveFailures = 0
            entry.nextDue = now.addingTimeInterval(entry.interval)
        case .failed:
            entry.consecutiveFailures += 1
            let factor = pow(2, Double(min(entry.consecutiveFailures - 1, 16)))
            let delay = min(entry.interval * factor, max(Self.maximumBackoff, entry.interval))
            entry.nextDue = now.addingTimeInterval(delay)
        }
        entries[moduleID] = entry
    }

    /// The gate refused to run a due poll; ask again later.
    public mutating func postpone(_ moduleID: String, at now: Date) {
        guard let entry = entries[moduleID] else { return }
        entries[moduleID]?.nextDue = now.addingTimeInterval(min(entry.interval, Self.pauseRecheckInterval))
    }

    /// Requests a prompt poll, e.g. after the user acted in the module's pane.
    public mutating func expedite(_ moduleID: String, at now: Date) {
        guard let entry = entries[moduleID], entry.nextDue > now else { return }
        entries[moduleID]?.nextDue = now
    }

    /// The system woke: overdue checks run once, together, after settling.
    public mutating func wake(at now: Date) {
        let settled = now.addingTimeInterval(Self.wakeSettleDelay)
        for (moduleID, entry) in entries where entry.nextDue < settled {
            entries[moduleID]?.nextDue = settled
        }
    }
}
