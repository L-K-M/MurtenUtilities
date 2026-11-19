import Foundation

/// What a confirmed inventory reset achieved, entry by entry, judged by
/// reading the databases again afterwards. `tccutil` reporting success is
/// not enough: a running app can ask again at once, and organization
/// policy can keep an entry in place.
public struct InventoryResetResult: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// The command succeeded and the entry is gone from a fresh read.
        case removed
        /// The command succeeded but the entry is still recorded.
        case stillRecorded
        /// `tccutil` reported failure; the detail is its answer.
        case failed(String)
        /// `tccutil` timed out or said more than could be checked, and the
        /// entry is still recorded; the detail says which.
        case uncertain(String)
        /// The command succeeded but its database could not be read again.
        case unverified
        /// Not something `tccutil` can reset; only System Settings can.
        case skipped
    }

    public struct Item: Identifiable, Sendable {
        public let entry: InventoryEntry
        public let outcome: Outcome
        public var id: String { entry.id }
    }

    public let items: [Item]

    public init(items: [Item]) { self.items = items }

    /// The key `commandFailures` uses for one command.
    public static func commandKey(bundleIdentifier: String, service: String) -> String {
        bundleIdentifier + "\u{1F}" + service
    }

    /// Judges each requested entry. `commandFailures` holds every command
    /// `tccutil` reported failing, `uncertainCommands` every one whose
    /// outcome it left open (a timeout, truncated output), both by
    /// `commandKey`; `after` is the fresh read, nil when there is none. An
    /// uncertain command is judged by the fresh read: gone is removed.
    public static func assess(requested: [InventoryEntry], skipped: [InventoryEntry],
                              commandFailures: [String: String], uncertainCommands: [String: String] = [:],
                              after: PermissionInventory?) -> InventoryResetResult {
        let remaining = Set(after?.entries.map(\.id) ?? [])
        let readable = Set(after?.sources.compactMap { source -> PermissionRecord.Database? in
            if case .read = source.reading { return source.database }
            return nil
        } ?? [])

        var items: [Item] = requested.map { entry in
            let key = commandKey(bundleIdentifier: entry.record.client, service: entry.service.resetName)
            if let failure = commandFailures[key] { return Item(entry: entry, outcome: .failed(failure)) }
            guard readable.contains(entry.record.database) else { return Item(entry: entry, outcome: .unverified) }
            guard remaining.contains(entry.id) else { return Item(entry: entry, outcome: .removed) }
            if let detail = uncertainCommands[key] { return Item(entry: entry, outcome: .uncertain(detail)) }
            return Item(entry: entry, outcome: .stillRecorded)
        }
        items += skipped.map { Item(entry: $0, outcome: .skipped) }
        return InventoryResetResult(items: items)
    }

    public func count(_ outcome: Outcome) -> Int {
        items.filter { $0.outcome == outcome }.count
    }

    public var failedCount: Int {
        items.filter { if case .failed = $0.outcome { return true }; return false }.count
    }

    public var uncertainCount: Int {
        items.filter { if case .uncertain = $0.outcome { return true }; return false }.count
    }

    /// One sentence per kind of outcome, for the notice and the sheet.
    public var summary: String {
        var parts: [String] = []
        let removed = count(.removed)
        if removed > 0 { parts.append("Removed \(Self.entries(removed)).") }
        let still = count(.stillRecorded)
        if still > 0 {
            parts.append("\(Self.entries(still)) \(still == 1 ? "is" : "are") still recorded. A running app may have asked again, or your organization may manage \(still == 1 ? "it" : "them").")
        }
        if failedCount > 0 {
            parts.append("tccutil did not reset \(Self.entries(failedCount)).")
        }
        if uncertainCount > 0 {
            parts.append("tccutil's outcome was uncertain for \(Self.entries(uncertainCount)), and \(uncertainCount == 1 ? "it is" : "they are") still recorded.")
        }
        let unverified = count(.unverified)
        if unverified > 0 {
            parts.append("\(Self.entries(unverified)) could not be checked afterwards.")
        }
        let skipped = count(.skipped)
        if skipped > 0 {
            parts.append("\(Self.entries(skipped)) can only be removed in System Settings.")
        }
        return parts.isEmpty ? "Nothing was reset." : parts.joined(separator: " ")
    }

    private static func entries(_ count: Int) -> String {
        count == 1 ? "1 entry" : "\(count) entries"
    }
}
