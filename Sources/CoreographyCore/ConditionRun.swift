import Foundation

/// Since when a condition has held at every poll in an unbroken run. A
/// watcher polls every 15 minutes, so "held at two polls in a row" is the
/// closest it can come to "sustained"; a gap longer than `maximumGap`
/// (sleep, a paused watcher) starts a new run.
public struct ConditionRun: Sendable {
    public static let maximumGap: TimeInterval = 45 * 60

    private var since: Date?
    private var lastHeld: Date?

    public init() {}

    /// Returns when the current run started, or nil when the condition does
    /// not hold now.
    public mutating func record(holds: Bool, at now: Date) -> Date? {
        guard holds else {
            since = nil
            lastHeld = nil
            return nil
        }
        if let since, let lastHeld, now.timeIntervalSince(lastHeld) <= Self.maximumGap {
            self.lastHeld = now
            return since
        }
        since = now
        lastHeld = now
        return now
    }
}
