import Foundation

/// One row of a macOS privacy database, as read. It is evidence of a
/// recorded decision, not of effective access: organization policy and the
/// running process's identity still decide.
public struct PermissionRecord: Hashable, Sendable {
    /// Which database holds it.
    public enum Database: String, CaseIterable, Sendable {
        /// `/Library/Application Support/com.apple.TCC/TCC.db`: every account.
        case system
        /// `~/Library/Application Support/com.apple.TCC/TCC.db`: this account.
        case user

        public var title: String {
            switch self {
            case .system: return "For all users"
            case .user: return "For you"
            }
        }
    }

    /// The database's `client_type`.
    public enum ClientKind: Hashable, Sendable {
        case bundleIdentifier
        case path

        /// 0 is a bundle identifier, 1 an absolute path; nil for any other.
        public init?(clientType: Int) {
            switch clientType {
            case 0: self = .bundleIdentifier
            case 1: self = .path
            default: return nil
            }
        }
    }

    /// The database's `auth_value`.
    public enum Decision: Hashable, Sendable {
        case denied, unknown, allowed, limited
        /// A value this version does not know, kept rather than guessed.
        case other(Int)

        public init(authValue: Int) {
            switch authValue {
            case 0: self = .denied
            case 1: self = .unknown
            case 2: self = .allowed
            case 3: self = .limited
            default: self = .other(authValue)
            }
        }

        public var title: String {
            switch self {
            case .denied: return "Denied"
            case .unknown: return "Not decided"
            case .allowed: return "Allowed"
            case .limited: return "Limited"
            case .other(let value): return "Value \(value)"
            }
        }

        /// Whether the record lets the app use the service at all.
        public var grantsAccess: Bool { self == .allowed || self == .limited }
    }

    public var database: Database
    /// The service identifier, for example `kTCCServiceCamera`.
    public var service: String
    public var client: String
    public var clientKind: ClientKind
    public var decision: Decision
    /// The database's `auth_reason`.
    public var reason: Int
    /// The code requirement recorded with the decision (`csreq`).
    public var requirement: Data?
    /// For Automation, the app being controlled (`indirect_object_identifier`).
    public var target: String?
    public var lastModified: Date?
    /// Set by device management: a `managed_overrides` row or an MDM reason.
    public var isManaged: Bool

    public init(database: Database, service: String, client: String, clientKind: ClientKind,
                decision: Decision, reason: Int = 0, requirement: Data? = nil, target: String? = nil,
                lastModified: Date? = nil, isManaged: Bool = false) {
        self.database = database
        self.service = service
        self.client = client
        self.clientKind = clientKind
        self.decision = decision
        self.reason = reason
        self.requirement = requirement
        self.target = target
        self.lastModified = lastModified
        self.isManaged = isManaged || reason == Self.mdmPolicyReason
    }

    /// Stable across reads: database, service, client and target.
    public var key: String {
        [database.rawValue, service, clientKind == .path ? "path" : "bundle", client, target ?? ""].joined(separator: "\u{1F}")
    }

    // MARK: - Reasons

    /// `auth_reason` 6. tccd's own migration writes managed rows with it.
    public static let mdmPolicyReason = 6

    /// tccd's names for the reasons it records (its own strings), or nil
    /// for a value without a published name.
    public var reasonTitle: String? {
        switch reason {
        case 1: return "Error"
        case 2: return "User Consent"
        case 3: return "User Set"
        case 4: return "System Set"
        case 5: return "Service Policy"
        case 6: return "MDM Policy"
        case 7: return "Override Policy"
        case 8: return "Missing Usage String"
        case 9: return "Prompt Timeout"
        case 10: return "Preflight Unknown"
        case 11: return "Entitled"
        case 12: return "App Type Policy"
        default: return nil
        }
    }

    // MARK: - Managed rows

    /// The `access` rows with `managed_overrides` folded in: an override for
    /// a row's key marks that row managed and, when it sets a decision,
    /// takes it; an override without a row stands on its own.
    ///
    /// tccd's upsert can store only `admin_auth_value` (whether a standard
    /// user may change the setting), leaving `auth_value` at its default 1.
    /// Such an override decides nothing: a row it matches keeps its own
    /// decision, and one without a row is not listed.
    public static func merging(access: [PermissionRecord], managed: [PermissionRecord]) -> [PermissionRecord] {
        var overrides: [String: PermissionRecord] = [:]
        for record in managed { overrides[record.key] = record }
        var result: [PermissionRecord] = []
        for var record in access {
            if let override = overrides.removeValue(forKey: record.key) {
                if override.decision != .unknown { record.decision = override.decision }
                record.isManaged = true
            }
            result.append(record)
        }
        for record in managed where overrides[record.key] != nil {
            overrides[record.key] = nil
            guard record.decision != .unknown else { continue }
            var record = record
            record.isManaged = true
            result.append(record)
        }
        return result
    }
}
