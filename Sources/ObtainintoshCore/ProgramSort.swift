import Foundation

/// The table's sort order: a column and a direction, with the name as the
/// ascending tiebreaker whatever the direction.
public struct ProgramSort: Equatable, Sendable {
    public enum Field: String, CaseIterable, Sendable {
        case name
        case current
        case latest
        case status
    }

    public var field: Field
    public var ascending: Bool

    public init(field: Field = .name, ascending: Bool = true) {
        self.field = field
        self.ascending = ascending
    }

    /// Clicking the sorted column flips it; another column starts ascending.
    public mutating func select(_ field: Field) {
        if self.field == field {
            ascending.toggle()
        } else {
            self.field = field
            ascending = true
        }
    }

    public func sorted(_ apps: [TrackedApp]) -> [TrackedApp] {
        apps.sorted { compare($0, $1) == .orderedAscending }
    }

    public func compare(_ a: TrackedApp, _ b: TrackedApp) -> ComparisonResult {
        var result = Self.compare(a, b, by: field)
        if !ascending { result = Self.reversed(result) }
        if result != .orderedSame { return result }
        return VersionComparison.collate(a.name, b.name)
    }

    private static func compare(_ a: TrackedApp, _ b: TrackedApp, by field: Field) -> ComparisonResult {
        switch field {
        case .name:
            return VersionComparison.collate(a.name, b.name)
        case .current:
            return VersionComparison.compareForSorting(a.currentVersion, b.currentVersion)
        case .latest:
            return VersionComparison.compareForSorting(a.latestVersion, b.latestVersion)
        case .status:
            let left = statusRank(a)
            let right = statusRank(b)
            if left == right { return .orderedSame }
            return left < right ? .orderedAscending : .orderedDescending
        }
    }

    /// Updates first, then programs without a release found, installed
    /// ones, and the rest.
    static func statusRank(_ app: TrackedApp) -> Int {
        if VersionComparison.hasUpdate(current: app.currentVersion, latest: app.latestVersion) { return 0 }
        if ProgramStatus.nonEmpty(app.latestVersion) == nil { return 1 }
        if ProgramStatus.nonEmpty(app.currentVersion) != nil { return 2 }
        return 3
    }

    private static func reversed(_ result: ComparisonResult) -> ComparisonResult {
        switch result {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }
}
