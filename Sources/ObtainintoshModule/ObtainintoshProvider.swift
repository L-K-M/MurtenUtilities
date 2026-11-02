import SwiftUI
import MurtenCore
import MurtenModuleKit
import ObtainintoshCore
import ObtainintoshServices

/// Obtainintosh inside Murten Utilities: the window as a pane, its settings
/// as a tab, and a background check for newer releases of installed
/// programs. It downloads and reveals; it never installs or replaces.
@MainActor
public final class ObtainintoshProvider: SuiteModuleProvider {
    public let moduleID = UpdateFinding.moduleID
    /// A suggestion opens the pane, which checks again. It preselects
    /// nothing (docs/modules.md, What a suggestion may preselect).
    public let routeActions: [String: Set<String>] = [UpdateFinding.routeAction: []]
    public let watch: WatcherRegistration?

    let model: ObtainintoshModel

    public convenience init(context: ModuleContext) {
        self.init(context: context, environment: .live())
    }

    init(context: ModuleContext, environment: ObtainintoshEnvironment) {
        model = ObtainintoshModel(environment: environment, defaults: context.defaults,
                                  requestRecheck: context.requestRecheck)
        watch = WatcherRegistration(watcher: ObtainintoshWatcher(observer: environment.observer), rule: UpdateRule())
    }

    public func makePane(route: ModuleRoute?) -> AnyView {
        AnyView(ObtainintoshPane(model: model, route: route))
    }

    public func makeSettings() -> AnyView? {
        AnyView(ObtainintoshSettingsView(model: model, presentation: .settingsWindow))
    }

    public var interruptionWarning: String? { model.interruptionWarning }
}
