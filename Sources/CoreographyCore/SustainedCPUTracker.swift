import Foundation

/// Average CPU use per process over about the last hour, from the cumulative
/// CPU time read at each poll. Deltas between polls, never instantaneous
/// rates: a 15-minute cadence still accounts for every second in between.
///
///     poll     0 min   15     30     45     60     75
///     Xcode    100 s  1000 s 1900 s 2800 s 3700 s 4600 s
///                                           └ 3600 s over 60 min = 1.0 core
///                                                  └ 3600 s over 60 min (baseline 15 min)
public struct SustainedCPUTracker: Sendable {
    /// One process's use over its window.
    public struct Usage: Hashable, Sendable {
        public let name: String
        public let pid: Int32
        public let cpuSeconds: Double
        public let span: TimeInterval

        /// 1.0 is one core busy the whole span.
        public var averageCores: Double { span > 0 ? cpuSeconds / span : 0 }
    }

    public struct Outcome: Sendable {
        /// Every process with a full window, busiest first.
        public let usage: [Usage]
        /// True once the tracker has read processes for a full window: only
        /// then is a process missing from `usage` known to be quiet or gone,
        /// rather than not yet measured.
        public let coversWindow: Bool
    }

    /// The span an average covers. A poll that arrives a little early still
    /// counts, so the baseline only needs to be `window - tolerance` old.
    public static let window: TimeInterval = 60 * 60
    public static let windowTolerance: TimeInterval = 5 * 60
    /// Readings older than this are dropped: after a long pause (sleep, the
    /// watcher switched off) averages start over instead of spanning it.
    public static let maximumSpan: TimeInterval = 4 * 60 * 60

    private struct Key: Hashable, Sendable {
        let pid: Int32
        let startedAt: UInt64
    }

    private struct Reading: Sendable {
        let time: Date
        let cpuNanoseconds: UInt64
    }

    private var history: [Key: [Reading]] = [:]
    /// Successful reads, oldest first, within `maximumSpan`.
    private var reads: [Date] = []

    public init() {}

    /// Folds in one successful read of every readable process.
    public mutating func record(_ processes: [ProcessCPUTime], at now: Date) -> Outcome {
        let oldest = now.addingTimeInterval(-Self.maximumSpan)
        reads = reads.filter { $0 >= oldest && $0 < now } + [now]

        var next: [Key: [Reading]] = [:]
        var usage: [Usage] = []
        for process in processes {
            let key = Key(pid: process.pid, startedAt: process.startedAt)
            var readings = (history[key] ?? []).filter { $0.time >= oldest && $0.time < now }
            // A counter that went backwards is not a history to trust.
            if let last = readings.last, last.cpuNanoseconds > process.cpuNanoseconds { readings = [] }

            if let baseline = Self.baseline(in: readings, at: now) {
                let cpu = Double(process.cpuNanoseconds - baseline.cpuNanoseconds) / 1_000_000_000
                usage.append(Usage(name: process.name, pid: process.pid, cpuSeconds: cpu,
                                   span: now.timeIntervalSince(baseline.time)))
            }

            readings.append(Reading(time: now, cpuNanoseconds: process.cpuNanoseconds))
            next[key] = Self.trimmed(readings, at: now)
        }
        // Processes that exited leave with this read.
        history = next

        let covers = reads.first.map { now.timeIntervalSince($0) >= Self.window - Self.windowTolerance } ?? false
        return Outcome(usage: usage.sorted { $0.averageCores > $1.averageCores }, coversWindow: covers)
    }

    /// The newest reading old enough to measure a full window from.
    private static func baseline(in readings: [Reading], at now: Date) -> Reading? {
        readings.last { now.timeIntervalSince($0.time) >= window - windowTolerance }
    }

    /// Keeps today's baseline and everything newer: later baselines can
    /// only be newer still.
    private static func trimmed(_ readings: [Reading], at now: Date) -> [Reading] {
        guard let index = readings.lastIndex(where: { now.timeIntervalSince($0.time) >= window - windowTolerance }) else {
            return readings
        }
        return Array(readings[index...])
    }
}
