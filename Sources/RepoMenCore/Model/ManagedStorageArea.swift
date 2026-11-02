import Foundation

/// Storage whose owner must decide what to remove. Never a CleanableItem: these
/// measurements cannot enter reclaim totals, checkboxes or watch automation.
package struct ManagedStorageArea: Identifiable, Sendable {
    package enum State: Equatable, Sendable {
        case unmeasured
        case missing
        case measured(Int64)
        case partial(Int64, String)
        case failed(String)
    }

    package let id: String
    package let title: String
    package let path: String
    package let instructions: String
    package let documentationURL: URL
    package let applicationBundleIDs: [String]
    package var command: String? = nil
    package var state: State = .unmeasured
}
