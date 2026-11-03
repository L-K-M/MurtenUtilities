import Foundation
import ShortkingCore

/// Conflicts the user acknowledged in the pane, by
/// `Conflict.acknowledgementSignature`, in the module's defaults.
///
/// The pane writes; the watcher only calls `signatures`. An acknowledged conflict
/// stays visible in the pane; it only stops being a suggestion.
///
/// `@unchecked Sendable`: the only state is a `UserDefaults`, which is
/// thread-safe, and the watcher reads it off the main actor.
final class ConflictAcknowledgements: @unchecked Sendable {

    static let key = "acknowledgedConflicts"

    /// Oldest acknowledgements drop out beyond this, so the list cannot grow
    /// without bound as fights come and go.
    static let limit = 500

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var signatures: Set<String> {
        Set(stored)
    }

    func contains(_ signature: String) -> Bool {
        stored.contains(signature)
    }

    func acknowledge(_ signature: String) {
        var list = stored.filter { $0 != signature }
        list.append(signature)
        defaults.set(Array(list.suffix(Self.limit)), forKey: Self.key)
    }

    func withdraw(_ signature: String) {
        defaults.set(stored.filter { $0 != signature }, forKey: Self.key)
    }

    /// Oldest first.
    private var stored: [String] {
        defaults.stringArray(forKey: Self.key) ?? []
    }
}
