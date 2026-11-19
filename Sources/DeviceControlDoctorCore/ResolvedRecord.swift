import Foundation

/// Whether an app still satisfies the code requirement macOS recorded with
/// its decision. A mismatch means the app changed since it was allowed (an
/// update by another developer, a re-signed or tampered copy), so the
/// decision no longer applies to it.
public enum SignatureCheck: Hashable, Sendable {
    case matches
    case changed
    /// No requirement was recorded, the app is not on this Mac, or the
    /// check could not run; the reason says which.
    case notChecked(String)
}

/// A record with what the module found out about its client (and, for
/// Automation, the app it controls). The input to `PermissionInventory`.
public struct ResolvedRecord: Sendable {
    public var record: PermissionRecord
    public var client: ClientStatus
    public var signature: SignatureCheck
    public var target: ClientStatus?

    public init(record: PermissionRecord, client: ClientStatus, signature: SignatureCheck, target: ClientStatus? = nil) {
        self.record = record
        self.client = client
        self.signature = signature
        self.target = target
    }
}
