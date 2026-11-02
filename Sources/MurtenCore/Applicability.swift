import Foundation

/// Whether a module can work on this Mac. An inapplicable module never runs
/// its watcher, never surfaces a suggestion and never opens a pane that
/// cannot work; the home screen shows the reason instead.
public enum Applicability: Equatable, Sendable {
    case applicable
    /// The reason is user-facing, e.g. "Docker is not installed".
    case inapplicable(reason: String)

    public var isApplicable: Bool { self == .applicable }
}
