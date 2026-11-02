import Foundation
import MurtenCore

/// How the suite addresses DeviceControlDoctor: its module id and the one
/// action a suggestion may open with.
public enum DoctorRoute {
    public static let moduleID = "devicecontroldoctor"

    /// Opens the pane with one watched app selected. It selects; it never
    /// starts a reset or opens the repair sheet.
    public static let reviewAction = "review"

    /// The watched app's watch-list id (a UUID string).
    public static let appKey = "app"

    /// The provider's `routeActions`.
    public static let actions: [String: Set<String>] = [reviewAction: [appKey]]

    public static func review(appID: UUID) -> ModuleRoute {
        ModuleRoute(moduleID: moduleID, action: reviewAction, context: [appKey: appID.uuidString])
    }

    /// The watched app a route asks the pane to select, or nil for a bare
    /// route, another module's route or a malformed id.
    public static func appID(in route: ModuleRoute?) -> UUID? {
        guard let route, route.moduleID == moduleID, route.action == reviewAction,
              let value = route.context[appKey] else { return nil }
        return UUID(uuidString: value)
    }
}
