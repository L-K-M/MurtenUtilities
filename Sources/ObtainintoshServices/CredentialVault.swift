import Foundation
import ObtainintoshCore

/// The module's tokens: the GitHub token from Settings and each private
/// Forgejo program's application key. Values read or saved this session are
/// kept in memory, so the Keychain is asked at most once per item.
///
/// The background check reads only that memory (`cachedToken`), never the
/// Keychain, so it can never raise an access prompt.
public actor CredentialVault {
    public enum Account: Hashable, Sendable {
        case gitHub
        case forgejo(appID: String)

        var name: String {
            switch self {
            case .gitHub: return "github-token"
            case .forgejo(let appID): return "forgejo-key.\(appID)"
            }
        }
    }

    private let store: SecretStoring
    /// nil value: read and found absent.
    private var cache: [Account: String?] = [:]

    public init(store: SecretStoring) {
        self.store = store
    }

    /// The token if this session already read or saved it; never touches
    /// the Keychain.
    public func cachedToken(_ account: Account) -> String? {
        cache[account] ?? nil
    }

    /// The token, reading the Keychain once if needed. Call only for an
    /// action the user started: the read may prompt.
    public func token(_ account: Account) throws -> String? {
        if let cached = cache[account] { return cached }
        let value = try store.read(account: account.name)
        cache[account] = .some(value)
        return value
    }

    /// Saves a token; blank removes it.
    public func setToken(_ value: String?, for account: Account) throws {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            try store.delete(account: account.name)
            cache[account] = .some(nil)
        } else {
            try store.write(trimmed, account: account.name)
            cache[account] = .some(trimmed)
        }
    }
}
