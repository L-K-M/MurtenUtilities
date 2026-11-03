import Foundation
#if os(macOS)
import Security
#endif

public enum CredentialStoreError: Error, Equatable, Sendable {
    case unsupportedPlatform
    case keychain(status: Int32)
}

public protocol CredentialStoring: Sendable {
    func read() throws -> String?
    func save(_ secret: String) throws
    func delete() throws
    /// Whether a non-empty secret is stored, ideally without reading it.
    func contains() throws -> Bool
}

extension CredentialStoring {
    public func contains() throws -> Bool { try read()?.isEmpty == false }
}

/// The provider key lives only in the login Keychain: never in preferences,
/// history, logs, exports or MCP results (plan: in-app assistant credentials).
public struct KeychainCredentialStore: CredentialStoring {
    private let service: String
    private let account: String

    public init(service: String = "ch.lkmc.Coreography.provider", account: String = "anthropic") {
        self.service = service
        self.account = account
    }

    public func read() throws -> String? {
        #if os(macOS)
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw CredentialStoreError.keychain(status: status) }
        return String(decoding: data, as: UTF8.self)
        #else
        throw CredentialStoreError.unsupportedPlatform
        #endif
    }

    /// Asks for the item's attributes only. Reading its data can make macOS
    /// ask the person to allow access, for instance when another app (the
    /// standalone Coreography) saved it; showing whether a key exists must
    /// not prompt, only using it may.
    public func contains() throws -> Bool {
        #if os(macOS)
        var query = baseQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw CredentialStoreError.keychain(status: status) }
        return true
        #else
        throw CredentialStoreError.unsupportedPlatform
        #endif
    }

    /// Replaces the key in place, so a failed write never leaves the old one deleted.
    public func save(_ secret: String) throws {
        #if os(macOS)
        // Readable only while this Mac is unlocked, and never synced to other devices.
        let values: [String: Any] = [
            kSecValueData as String: Data(secret.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updated = SecItemUpdate(baseQuery() as CFDictionary, values as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw CredentialStoreError.keychain(status: updated) }
        let attributes = baseQuery().merging(values) { _, new in new }
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // Another writer, such as a second copy of the app, added it between the update and the add.
            let retried = SecItemUpdate(baseQuery() as CFDictionary, values as CFDictionary)
            guard retried == errSecSuccess else { throw CredentialStoreError.keychain(status: retried) }
            return
        }
        guard status == errSecSuccess else { throw CredentialStoreError.keychain(status: status) }
        #else
        throw CredentialStoreError.unsupportedPlatform
        #endif
    }

    public func delete() throws {
        #if os(macOS)
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status: status)
        }
        #else
        throw CredentialStoreError.unsupportedPlatform
        #endif
    }

    #if os(macOS)
    private func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    #endif
}
