import Foundation
import MurtenCore

/// Shortking's identity inside Murten Utilities and the routes its
/// suggestions open.
public enum ShortkingSuite {
    public static let moduleID = "shortking"

    /// Opens the Conflicts view scrolled to one shortcut. It selects nothing
    /// for an action: Shortking never rebinds anything.
    public static let conflictAction = "conflict"

    /// The shortcut a conflict route focuses, as `KeyCombo.groupingKey`.
    public static let comboContextKey = "combo"

    /// The provider's route allowlist.
    public static let routeActions: [String: Set<String>] = [conflictAction: [comboContextKey]]

    public static func conflictRoute(comboKey: String) -> ModuleRoute {
        ModuleRoute(moduleID: moduleID, action: conflictAction, context: [comboContextKey: comboKey])
    }
}
