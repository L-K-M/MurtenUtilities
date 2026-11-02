import Foundation
import MurtenCore

/// How the suite's background check reads one runner. Only a live process counts as
/// online; a stopped runner is offline; a state that could not be read proves nothing.
public enum RunnerHealthState: Equatable, Sendable {
    case online
    case stopped
    /// Disabled in launchd: the user turned it off on purpose.
    case disabled
    /// Process or launch service state could not be read.
    case unverifiable

    public init(_ snapshot: RunnerSnapshot) {
        if snapshot.isOnline { self = .online; return }
        switch snapshot.status {
        case .stopped: self = .stopped
        case .disabled: self = .disabled
        case .idle, .busy, .attention, .unknown: self = .unverifiable
        }
    }
}

/// What RunningMan remembers about each runner between looks, in memory only: when it
/// was last online, since when it has been offline, and whether RunningMan stopped it on
/// request. The background check and the pane's refreshes both feed it; neither writes
/// anything to disk for it.
public struct RunnerHealthMemory: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public var lastSeenOnline: Date?
        /// The first look that found the runner stopped after it was last online.
        public var offlineSince: Date?
        /// When RunningMan stopped, disabled or removed it on request, so being offline
        /// is what the user asked for. Cleared once the runner is seen online again.
        public var stoppedOnRequestAt: Date?

        public init(lastSeenOnline: Date? = nil, offlineSince: Date? = nil, stoppedOnRequestAt: Date? = nil) {
            self.lastSeenOnline = lastSeenOnline
            self.offlineSince = offlineSince
            self.stoppedOnRequestAt = stoppedOnRequestAt
        }
    }

    public private(set) var entries: [String: Entry] = [:]

    public init() {}

    /// A stop, disable or removal the user asked for; it lasts until the runner is online again.
    public mutating func acknowledgeStop(of runnerID: String, at date: Date) {
        entries[runnerID, default: Entry()].stoppedOnRequestAt = date
    }

    /// Folds one look at the runners in, dated when the look started reading. An
    /// unverifiable state changes nothing.
    public mutating func record(_ snapshots: [RunnerSnapshot], at now: Date) {
        for snapshot in snapshots {
            switch RunnerHealthState(snapshot) {
            case .online:
                // A look that started before an acknowledged stop saw the runner before it
                // stopped; it must not end the acknowledgement.
                if let stopped = entries[snapshot.id]?.stoppedOnRequestAt, now < stopped { continue }
                entries[snapshot.id] = Entry(lastSeenOnline: now)
            case .stopped:
                if entries[snapshot.id]?.offlineSince == nil { entries[snapshot.id, default: Entry()].offlineSince = now }
            case .disabled:
                entries[snapshot.id]?.offlineSince = nil
            case .unverifiable:
                break
            }
        }
    }

    /// Drops runners that are no longer installed.
    public mutating func forget(allExcept runnerIDs: Set<String>) {
        entries = entries.filter { runnerIDs.contains($0.key) }
    }
}

/// Turns one look at the runners into the suite's observation: a `runner-offline` finding
/// per runner that should be running and is not, with the time it was first seen offline.
/// Pure, so every case is tested with fixture snapshots.
public enum RunnerHealthCheck {
    public static let moduleID = "runningman"
    public static let condition = "runner-offline"

    /// Evidence keys of a `runner-offline` finding.
    public enum Evidence {
        public static let name = "name"
        public static let offlineSince = "offlineSince"
        public static let reason = "reason"
    }

    /// Why a stopped runner is expected to be running.
    public enum Reason: String, Sendable {
        /// Its login service starts it at login.
        case startsAtLogin = "starts-at-login"
        /// It was online earlier and stopped without a request from RunningMan.
        case stoppedUnexpectedly = "stopped-unexpectedly"
    }

    /// - Parameters:
    ///   - snapshots: every runner discovery found, with its process and launchd state.
    ///   - skippedDirectories: runner folders the check may not read (privacy-protected).
    ///   - discoveryComplete: discovery read every candidate it found, so `snapshots` are all
    ///     the runners there are and a suggestion for any other runner can resolve.
    ///   - memory: updated with this look; the caller keeps it for the next one.
    public static func observation(of snapshots: [RunnerSnapshot], skippedDirectories: [URL] = [],
                                   discoveryComplete: Bool = false,
                                   memory: inout RunnerHealthMemory, at now: Date) -> WatchObservation {
        memory.record(snapshots, at: now)

        var findings: [Finding] = []
        var completed = Set<FindingScope>()
        var failures: [ObservationFailure] = []

        for snapshot in snapshots {
            let scope = FindingScope(snapshot.id)
            switch RunnerHealthState(snapshot) {
            case .unverifiable:
                failures.append(ObservationFailure(kind: .failed, scope: scope,
                    message: "\(snapshot.runner.name): its process and launch service state could not be read."))
            case .online, .disabled:
                completed.insert(scope)
            case .stopped:
                completed.insert(scope)
                if let finding = offlineFinding(for: snapshot, entry: memory.entries[snapshot.id], at: now) {
                    findings.append(finding)
                }
            }
        }

        // Only complete discovery proves a runner was removed; skipped folders still exist.
        if discoveryComplete {
            let present = Set(snapshots.map(\.id)).union(skippedDirectories.map(\.path))
            for runnerID in memory.entries.keys where !present.contains(runnerID) {
                completed.insert(FindingScope(runnerID))
            }
            memory.forget(allExcept: present)
        }

        for directory in skippedDirectories {
            failures.append(ObservationFailure(kind: .permissionDenied, scope: FindingScope(directory.path),
                message: "\(directory.lastPathComponent) is in a folder macOS protects, so the background check skips it. Open RunningMan to check it."))
        }

        // Skipped folders and unreadable runners are listed as failures, so they count as
        // existing; only runners discovery no longer finds resolve.
        return WatchObservation(moduleID: moduleID, observedAt: now, findings: findings,
                                completedScopes: completed, failures: failures,
                                coverage: discoveryComplete ? .exhaustive : .listed)
    }

    /// System services are left out: RunningMan only observes them and cannot restart them.
    private static func offlineFinding(for snapshot: RunnerSnapshot, entry: RunnerHealthMemory.Entry?,
                                       at now: Date) -> Finding? {
        guard snapshot.runner.serviceDomain == .user, let entry, entry.stoppedOnRequestAt == nil,
              let offlineSince = entry.offlineSince else { return nil }

        let reason: Reason
        if snapshot.startsAtLogin {
            reason = .startsAtLogin
        } else if entry.lastSeenOnline != nil {
            reason = .stoppedUnexpectedly
        } else {
            // Never seen running and not set to start: nothing says it should be running.
            return nil
        }

        return Finding(moduleID: moduleID, condition: condition, scope: FindingScope(snapshot.id), observedAt: now,
                       evidence: [Evidence.name: .text(snapshot.runner.name),
                                  Evidence.offlineSince: .date(offlineSince),
                                  Evidence.reason: .text(reason.rawValue)])
    }
}
