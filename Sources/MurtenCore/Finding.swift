import Foundation

/// What a finding is about. Identity includes scope so two targets reporting
/// the same condition never share a suggestion: two Docker endpoints become
/// `unix:///var/run/docker.sock` and `ssh://build-box`, not one "docker" key.
/// Checks with a single target use `.local`.
public struct FindingScope: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let local = FindingScope("local")

    public var description: String { rawValue }
}

/// Typed evidence a rule reads to decide whether a finding warrants a
/// suggestion. Units live in the case, so a rule never guesses whether
/// "size" meant bytes or megabytes.
public enum EvidenceValue: Hashable, Codable, Sendable {
    case bytes(Int64)
    case count(Int)
    case seconds(TimeInterval)
    case date(Date)
    case text(String)
}

/// One condition a watcher observed on one target at one time, e.g.
/// "dockvac / reclaimable / unix:///var/run/docker.sock, 8.2 GB". A finding is
/// an observation, not a verdict: the module's `SuggestionRule` decides
/// whether it is worth the user's attention.
public struct Finding: Hashable, Codable, Sendable {
    public let moduleID: String
    /// Module-defined condition, e.g. "reclaimable" or "runner-offline".
    public let condition: String
    public let scope: FindingScope
    public let observedAt: Date
    public let evidence: [String: EvidenceValue]

    public init(moduleID: String, condition: String, scope: FindingScope = .local,
                observedAt: Date, evidence: [String: EvidenceValue] = [:]) {
        self.moduleID = moduleID
        self.condition = condition
        self.scope = scope
        self.observedAt = observedAt
        self.evidence = evidence
    }

    public var key: SuggestionKey {
        SuggestionKey(moduleID: moduleID, condition: condition, scope: scope)
    }

    // MARK: - Typed evidence access

    public func bytes(_ name: String) -> Int64? {
        guard case .bytes(let value)? = evidence[name] else { return nil }
        return value
    }

    public func count(_ name: String) -> Int? {
        guard case .count(let value)? = evidence[name] else { return nil }
        return value
    }

    public func seconds(_ name: String) -> TimeInterval? {
        guard case .seconds(let value)? = evidence[name] else { return nil }
        return value
    }

    public func date(_ name: String) -> Date? {
        guard case .date(let value)? = evidence[name] else { return nil }
        return value
    }

    public func text(_ name: String) -> String? {
        guard case .text(let value)? = evidence[name] else { return nil }
        return value
    }
}
