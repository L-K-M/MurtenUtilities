import Foundation
#if canImport(Security)
import Security
#endif
import ObtainintoshCore

/// Generic passwords in the login Keychain under one service.
///
/// The suite is ad-hoc signed, so its designated requirement changes with
/// every build and macOS may ask before handing an item to a new build
/// (PLAN.md, *Signing*). Reads therefore happen only in response to
/// something the user did in the pane; the background check never reads.
public struct KeychainSecretStore: SecretStoring {
    public static let service = "ch.lkmc.MurtenUtilities.obtainintosh"

    private let service: String

    public init(service: String = KeychainSecretStore.service) {
        self.service = service
    }

    public func read(account: String) throws -> String? {
        #if canImport(Security)
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw ObtainintoshError("The token could not be read from your login Keychain (\(Self.describe(status))).")
        }
        return value
        #else
        return nil
        #endif
    }

    public func write(_ value: String, account: String) throws {
        #if canImport(Security)
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8),
                                         kSecAttrLabel as String: "Murten Utilities: Obtainintosh"]
        let status = SecItemUpdate(baseQuery(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addition = baseQuery(account)
            attributes.forEach { addition[$0.key] = $0.value }
            addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let added = SecItemAdd(addition as CFDictionary, nil)
            guard added == errSecSuccess else {
                throw ObtainintoshError("The token could not be saved in your login Keychain (\(Self.describe(added))).")
            }
        } else if status != errSecSuccess {
            throw ObtainintoshError("The token could not be updated in your login Keychain (\(Self.describe(status))).")
        }
        #else
        throw ObtainintoshError("Tokens need the macOS Keychain.")
        #endif
    }

    public func delete(account: String) throws {
        #if canImport(Security)
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ObtainintoshError("The token could not be removed from your login Keychain (\(Self.describe(status))).")
        }
        #endif
    }

    #if canImport(Security)
    private func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func describe(_ status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
    }
    #endif
}
