import Foundation

/// A confirmed reset of some of one app's inventory entries:
/// `tccutil reset SERVICE BUNDLE_ID` per service. Bundle-scoped like
/// `RepairPlan`, but over every catalogued or recorded service rather than
/// the five device-control and recording ones. It cannot express a
/// service-wide reset or `All`, and it refuses entries `tccutil` must not
/// or cannot reset (macOS's own, managed, path clients).
public struct InventoryResetPlan: Sendable, Equatable {
    public let bundleIdentifier: String
    /// `tccutil` service names, each once, in the order given.
    public let services: [String]

    public init(entries: [InventoryEntry]) throws {
        guard let first = entries.first else { throw InventoryResetError.noEntries }
        guard entries.allSatisfy({ $0.record.client == first.record.client }) else { throw InventoryResetError.mixedClients }
        guard entries.allSatisfy(\.canReset) else { throw InventoryResetError.notResettable }
        var seen = Set<String>()
        var services: [String] = []
        for entry in entries {
            let name = entry.service.resetName
            guard Self.isServiceName(name) else { throw InventoryResetError.invalidService(entry.service.identifier) }
            if seen.insert(name).inserted { services.append(name) }
        }
        self.bundleIdentifier = first.record.client
        self.services = services
    }

    public var arguments: [[String]] { services.map { ["reset", $0, bundleIdentifier] } }

    /// Letters and digits only, and never `All`, which would widen the
    /// reset to every service.
    static func isServiceName(_ name: String) -> Bool {
        name != "All" && name.range(of: "\\A[A-Za-z][A-Za-z0-9]*\\z", options: .regularExpression) != nil
    }

    /// One plan per app for the given entries, skipping those `tccutil`
    /// cannot reset; those are left for System Settings.
    public static func plans(for entries: [InventoryEntry]) -> (plans: [InventoryResetPlan], skipped: [InventoryEntry]) {
        var skipped: [InventoryEntry] = []
        var byClient: [String: [InventoryEntry]] = [:]
        var order: [String] = []
        for entry in entries {
            guard entry.canReset, isServiceName(entry.service.resetName) else { skipped.append(entry); continue }
            if byClient[entry.record.client] == nil { order.append(entry.record.client) }
            byClient[entry.record.client, default: []].append(entry)
        }
        let plans = order.compactMap { client in byClient[client].flatMap { try? InventoryResetPlan(entries: $0) } }
        return (plans, skipped)
    }
}

public enum InventoryResetError: LocalizedError, Equatable {
    case noEntries, mixedClients, notResettable, invalidService(String)

    public var errorDescription: String? {
        switch self {
        case .noEntries: return "Select at least one permission to reset."
        case .mixedClients: return "A reset applies to one app at a time."
        case .notResettable: return "Some of these entries belong to macOS, are managed by your organization, or are recorded by file path. Manage them in System Settings."
        case .invalidService(let service): return "\(service) is not a service tccutil can reset."
        }
    }
}
