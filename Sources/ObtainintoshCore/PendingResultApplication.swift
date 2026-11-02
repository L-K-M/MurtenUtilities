import Foundation

/// What a check did with one program's result: written, or discarded because
/// the program moved out from under it.
public enum PendingResultApplication: Equatable, Sendable {
    case applied
    case appRemoved
    case dependenciesChanged
}
