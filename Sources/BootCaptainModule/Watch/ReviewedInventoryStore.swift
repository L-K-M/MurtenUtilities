import Foundation
import BootCaptainCore

/// What the background check finds when it looks for the reviewed inventory.
public enum ReviewedInventoryLookup: Sendable, Equatable {
    /// The pane has never completed a scan, so there is nothing to compare.
    case notYetReviewed
    /// Stored, but in a shape this build cannot read.
    case unreadable
    case reviewed(ReviewedInventory)
}

/// Read access to the reviewed inventory: all the background check gets.
public protocol ReviewedInventoryReading: Sendable {
    func reviewedInventory() -> ReviewedInventoryLookup
}

/// Keeps the reviewed inventory in the module's preferences
/// (`ModuleContext.defaults`). The pane writes through `save`; the watcher
/// holds it as `ReviewedInventoryReading` and only reads.
public final class ReviewedInventoryStore: ReviewedInventoryReading, @unchecked Sendable {
    // UserDefaults is thread-safe; the store holds no other state.
    public static let defaultsKey = "reviewedStartupInventory"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func reviewedInventory() -> ReviewedInventoryLookup {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return .notYetReviewed }
        guard let inventory = try? JSONDecoder().decode(ReviewedInventory.self, from: data),
              inventory.version == ReviewedInventory.currentVersion else { return .unreadable }
        return .reviewed(inventory)
    }

    /// Replaces the reviewed inventory. False when it could not be encoded.
    @discardableResult
    public func save(_ inventory: ReviewedInventory) -> Bool {
        guard let data = try? JSONEncoder().encode(inventory) else { return false }
        defaults.set(data, forKey: Self.defaultsKey)
        return true
    }
}
