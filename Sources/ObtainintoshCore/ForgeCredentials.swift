import Foundation

/// Credentials for a self-hosted forge instance: the account name plus the
/// application key generated under Settings → Applications. Descriptions
/// redact the key, so a stray `print` cannot leak it.
public struct ForgeCredentials: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    public let username: String?
    public let token: String?

    /// Blank and whitespace-only entries are dropped, so a half-filled form
    /// behaves like no credentials instead of sending an empty key.
    public init(username: String? = nil, token: String? = nil) {
        func clean(_ value: String?) -> String? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                return nil
            }
            return trimmed
        }
        self.username = clean(username)
        self.token = clean(token)
    }

    /// Credentials kept only for a forge that authenticates with them, so a
    /// key can never be parked against a source that would never send it.
    /// Exhaustive on purpose: a new forge has to make this decision.
    public static func forSource(_ sourceType: SourceType, username: String?, token: String?) -> ForgeCredentials {
        switch sourceType {
        case .forgejo: return ForgeCredentials(username: username, token: token)
        case .github, .gitlab: return ForgeCredentials()
        }
    }

    /// The `Authorization` header value Forgejo expects, or nil when there is
    /// nothing to send.
    ///
    /// With a username, HTTP Basic carrying the key as the password: Forgejo
    /// reads an access token out of the Basic password, and Basic works on
    /// the web routes that serve release assets, not only on `/api/v1`.
    /// Without one, the API's own `token <key>` scheme. A username on its own
    /// authenticates nothing and is sent to nobody.
    public var authorizationHeader: String? {
        guard let token else { return nil }
        guard let username else { return "token \(token)" }
        return "Basic " + Data("\(username):\(token)".utf8).base64EncodedString()
    }

    public var description: String {
        "ForgeCredentials(username: \(username ?? "nil"), token: \(token == nil ? "nil" : redactedSecret))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["username": username as Any,
                                "token": (token == nil ? nil : redactedSecret) as Any])
    }
}
