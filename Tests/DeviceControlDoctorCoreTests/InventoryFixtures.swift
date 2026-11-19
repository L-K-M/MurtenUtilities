import Foundation
@testable import DoctorCore

/// Hand-built evidence for the inventory tests, so each test states exactly
/// the records and clients it means.
enum InventoryFixtures {
    static let readAt = Date(timeIntervalSince1970: 1_800_000_000)

    static func record(service: String = "kTCCServiceCamera",
                       client: String = "com.foo",
                       clientKind: PermissionRecord.ClientKind = .bundleIdentifier,
                       decision: PermissionRecord.Decision = .allowed,
                       database: PermissionRecord.Database = .system,
                       reason: Int = 0,
                       target: String? = nil,
                       lastModified: Date? = nil,
                       isManaged: Bool = false) -> PermissionRecord {
        PermissionRecord(database: database, service: service, client: client, clientKind: clientKind,
                         decision: decision, reason: reason, target: target,
                         lastModified: lastModified, isManaged: isManaged)
    }

    static func client(name: String = "Foo",
                       presence: ClientStatus.Presence = .installed(path: "/Applications/Foo.app"),
                       isSystem: Bool = false,
                       appIdentifier: String? = "com.foo") -> ClientStatus {
        ClientStatus(name: name, presence: presence, isSystem: isSystem, appIdentifier: appIdentifier)
    }

    static func resolved(_ record: PermissionRecord,
                         client: ClientStatus? = nil,
                         signature: SignatureCheck = .matches,
                         target: ClientStatus? = nil) -> ResolvedRecord {
        ResolvedRecord(record: record, client: client ?? InventoryFixtures.client(), signature: signature, target: target)
    }

    static func inventory(_ resolved: [ResolvedRecord], sources: [DatabaseSource] = []) -> PermissionInventory {
        PermissionInventory(sources: sources, resolved: resolved, readAt: readAt)
    }

    /// An entry built directly, for tests that only need a record, a client
    /// and flags.
    static func entry(record: PermissionRecord, client: ClientStatus, flags: InventoryEntry.Flags) -> InventoryEntry {
        InventoryEntry(record: record, service: PrivacyService.named(record.service), client: client,
                       signature: .matches, target: nil, flags: flags)
    }
}
