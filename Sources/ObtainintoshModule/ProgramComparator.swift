import Foundation
import ObtainintoshCore

/// A table column's sort order, as `Table` asks for it.
struct ProgramComparator: SortComparator, Hashable {
    var field: ProgramSort.Field
    var order: SortOrder = .forward

    func compare(_ lhs: TrackedApp, _ rhs: TrackedApp) -> ComparisonResult {
        ProgramSort(field: field, ascending: order == .forward).compare(lhs, rhs)
    }
}
