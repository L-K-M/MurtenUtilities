import Foundation

/// A confirmed, bundle-scoped reset. A service-wide command cannot be
/// constructed here, even when organization policy leaves entries behind.
public struct RepairPlan: Sendable {
    public let bundleIdentifier: String
    public let services: [ResetService]
    public init(bundleIdentifier: String, services: Set<ResetService>) throws {
        guard ClientIdentifier.isBundleIdentifier(bundleIdentifier) else { throw RepairError.invalidIdentifier }
        guard !services.isEmpty else { throw RepairError.noServices }
        self.bundleIdentifier = bundleIdentifier
        self.services = ResetService.allCases.filter { services.contains($0) }
    }
    public var arguments: [[String]] { services.map { ["reset", $0.rawValue, bundleIdentifier] } }
}

public enum RepairError: LocalizedError {
    case invalidIdentifier, noServices
    public var errorDescription: String? {
        switch self {
        case .invalidIdentifier: return "This client is not a bundle identifier. Manage its permission in System Settings."
        case .noServices: return "Select at least one permission to reset."
        }
    }
}
