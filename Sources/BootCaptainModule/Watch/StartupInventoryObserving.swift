import Foundation
import BootCaptainCore

/// A folder the background check could not read completely.
public struct InventoryReadFailure: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// The folder exists but could not be listed.
        case unreadable
        /// The read stopped because its task was cancelled.
        case cancelled
    }

    public var kind: Kind
    public var path: String
    public var reason: String

    public init(kind: Kind, path: String, reason: String) {
        self.kind = kind
        self.path = path
        self.reason = reason
    }
}

/// What one read of the startup folders saw.
public struct StartupInventorySnapshot: Sendable, Equatable {
    public var items: [WatchedStartupItem]
    /// Bundle identifier → app name, for the apps in the folders read.
    public var installedApps: [String: String]
    /// Anything not read; a snapshot with failures never proves an item gone.
    public var failures: [InventoryReadFailure]

    public init(items: [WatchedStartupItem] = [], installedApps: [String: String] = [:],
                failures: [InventoryReadFailure] = []) {
        self.items = items
        self.installedApps = installedApps
        self.failures = failures
    }
}

/// The background check's only view of the system: it reads, never writes,
/// needs no privilege and never prompts. Tests substitute fixtures.
public protocol StartupInventoryObserving: Sendable {
    func observeInventory() async -> StartupInventorySnapshot
}
