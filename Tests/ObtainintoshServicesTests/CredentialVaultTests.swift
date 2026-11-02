import XCTest
import ObtainintoshCore
@testable import ObtainintoshServices

/// Secrets in memory, counting reads, standing in for the Keychain.
final class MemorySecretStore: SecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]
    private var readCount = 0

    init(_ values: [String: String] = [:]) {
        self.values = values
    }

    var reads: Int { lock.withLock { readCount } }
    var stored: [String: String] { lock.withLock { values } }

    func read(account: String) throws -> String? {
        lock.withLock {
            readCount += 1
            return values[account]
        }
    }

    func write(_ value: String, account: String) throws {
        lock.withLock { values[account] = value }
    }

    func delete(account: String) throws {
        lock.withLock { values[account] = nil }
    }
}

final class CredentialVaultTests: XCTestCase {
    func testTheCacheNeverTouchesTheStore() async {
        let store = MemorySecretStore(["github-token": "ghp_stored"])
        let vault = CredentialVault(store: store)

        let cached = await vault.cachedToken(.gitHub)
        XCTAssertNil(cached)
        XCTAssertEqual(store.reads, 0)
    }

    func testTheStoreIsReadOncePerItem() async throws {
        let store = MemorySecretStore(["github-token": "ghp_stored"])
        let vault = CredentialVault(store: store)

        let first = try await vault.token(.gitHub)
        let second = try await vault.token(.gitHub)
        let absent = try await vault.token(.forgejo(appID: "x"))
        let absentAgain = try await vault.token(.forgejo(appID: "x"))
        let cached = await vault.cachedToken(.gitHub)

        XCTAssertEqual(first, "ghp_stored")
        XCTAssertEqual(second, "ghp_stored")
        XCTAssertNil(absent)
        XCTAssertNil(absentAgain)
        XCTAssertEqual(cached, "ghp_stored")
        XCTAssertEqual(store.reads, 2)
    }

    func testSavingTrimsAndBlankRemoves() async throws {
        let store = MemorySecretStore()
        let vault = CredentialVault(store: store)

        try await vault.setToken("  key  ", for: .forgejo(appID: "app-1"))
        XCTAssertEqual(store.stored["forgejo-key.app-1"], "key")
        let saved = await vault.cachedToken(.forgejo(appID: "app-1"))
        XCTAssertEqual(saved, "key")

        try await vault.setToken("   ", for: .forgejo(appID: "app-1"))
        XCTAssertNil(store.stored["forgejo-key.app-1"])
        let removed = await vault.cachedToken(.forgejo(appID: "app-1"))
        XCTAssertNil(removed)
    }
}
