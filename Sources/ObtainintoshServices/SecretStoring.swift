import Foundation

/// Where secrets persist: the login Keychain in the app, memory in tests.
public protocol SecretStoring: Sendable {
    /// May show the system's Keychain access prompt for an ad-hoc signed build.
    func read(account: String) throws -> String?
    func write(_ value: String, account: String) throws
    func delete(account: String) throws
}
