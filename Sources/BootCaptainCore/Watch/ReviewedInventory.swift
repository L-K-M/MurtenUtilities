import Foundation

/// The startup inventory the user last reviewed in the pane: the identities
/// (`StartupItem.id`) of every item its scan listed. The pane writes it when
/// the first scan completes and whenever the user marks the list as
/// reviewed; the background check only reads it and reports what is new.
public struct ReviewedInventory: Codable, Sendable, Equatable {
    /// Bumped when the stored shape changes incompatibly.
    public static let currentVersion = 1

    public var version: Int
    public var reviewedAt: Date
    public var itemIDs: Set<String>

    public init(reviewedAt: Date, itemIDs: Set<String>) {
        self.version = Self.currentVersion
        self.reviewedAt = reviewedAt
        self.itemIDs = itemIDs
    }

    /// Whether `id` was in the reviewed list.
    public func contains(_ id: String) -> Bool {
        itemIDs.contains(id)
    }
}
