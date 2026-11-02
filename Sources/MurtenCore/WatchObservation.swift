import Foundation

/// Why a check, or one scope of it, could not be completed. A failure never
/// proves a condition resolved: it makes the previous finding stale.
public struct ObservationFailure: Hashable, Codable, Sendable, Error {
    public enum Kind: String, Codable, Sendable {
        /// A privacy grant or credential the watcher may not prompt for.
        case permissionDenied
        /// A required tool, socket or file is absent.
        case toolMissing
        /// The endpoint did not answer (offline daemon, unreachable host).
        case unreachable
        /// The endpoint answered with something the watcher cannot parse.
        case malformedResponse
        /// The check exceeded its cadence's timeout.
        case timedOut
        case failed
    }

    public let kind: Kind
    /// The scope that could not be checked; nil when the whole check failed.
    public let scope: FindingScope?
    /// Short, user-presentable diagnostic, e.g. "Docker is not running".
    public let message: String

    public init(kind: Kind, scope: FindingScope? = nil, message: String) {
        self.kind = kind
        self.scope = scope
        self.message = message
    }
}

/// The result of one watcher poll. It states which scopes completed, so the
/// ledger can tell "checked and absent" (resolved) from "not checked"
/// (unchanged) and "check failed" (stale).
///
///     endpoint A: completed, reclaimable 8 GB   → finding, scope completed
///     endpoint B: completed, nothing to report  → scope completed, no finding
///     endpoint C: socket refused                → failure for scope C
public struct WatchObservation: Sendable {
    public enum Outcome: Equatable, Sendable {
        case complete
        case partial
        case unavailable
    }

    public let moduleID: String
    public let observedAt: Date
    public let findings: [Finding]
    public let completedScopes: Set<FindingScope>
    public let failures: [ObservationFailure]

    public init(moduleID: String, observedAt: Date, findings: [Finding],
                completedScopes: Set<FindingScope>, failures: [ObservationFailure]) {
        self.moduleID = moduleID
        self.observedAt = observedAt
        self.findings = findings
        self.completedScopes = completedScopes
        self.failures = failures
    }

    /// Every listed scope was checked; findings may be empty.
    public static func complete(moduleID: String, at date: Date,
                                scopes: Set<FindingScope> = [.local],
                                findings: [Finding] = []) -> WatchObservation {
        WatchObservation(moduleID: moduleID, observedAt: date, findings: findings,
                    completedScopes: scopes, failures: [])
    }

    /// Nothing could be checked.
    public static func unavailable(moduleID: String, at date: Date,
                                   _ failure: ObservationFailure) -> WatchObservation {
        WatchObservation(moduleID: moduleID, observedAt: date, findings: [],
                    completedScopes: [], failures: [failure])
    }

    public var outcome: Outcome {
        if failures.isEmpty { return .complete }
        return completedScopes.isEmpty && findings.isEmpty ? .unavailable : .partial
    }
}
