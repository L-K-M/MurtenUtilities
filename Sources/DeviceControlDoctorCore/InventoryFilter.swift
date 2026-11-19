import Foundation

/// The inventory's sidebar filters.
public enum InventoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all, leftovers, lookAlikes, broken, highRisk

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "All apps"
        case .leftovers: return "Leftovers"
        case .lookAlikes: return "Look-alikes"
        case .broken: return "Broken"
        case .highRisk: return "High-risk"
        }
    }

    /// The flag an entry needs to pass, nil for every entry.
    public var flag: InventoryEntry.Flags? {
        switch self {
        case .all: return nil
        case .leftovers: return .leftover
        case .lookAlikes: return .lookAlike
        case .broken: return .broken
        case .highRisk: return .highRisk
        }
    }

    public func includes(_ entry: InventoryEntry) -> Bool {
        guard let flag else { return true }
        return entry.flags.contains(flag)
    }
}
