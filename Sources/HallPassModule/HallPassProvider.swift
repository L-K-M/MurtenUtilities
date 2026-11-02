import SwiftUI
import MurtenCore
import MurtenModuleKit

/// HallPass inside the suite: one pane, no watcher, no settings tab, no
/// menu section.
///
/// - No watcher: reading the exemptions already needs administrator
///   access, so any check stays a pane action (docs/modules.md, HallPass).
/// - No route actions: nothing suggests HallPass, so only the bare route
///   opens it and nothing is preselected.
/// - Applicable everywhere the suite runs: the exemption defaults need
///   macOS 15.5 and the suite's floor is 26.
@MainActor
public final class HallPassProvider: SuiteModuleProvider {
    public nonisolated static let moduleID = "hallpass"

    public let moduleID = HallPassProvider.moduleID
    /// Owned here, not by the pane, so a draft survives navigating home.
    let model: HallPassModel

    public convenience init(context: ModuleContext) {
        self.init(model: HallPassModel(defaults: context.defaults))
    }

    init(model: HallPassModel) {
        self.model = model
    }

    public func makePane(route: ModuleRoute?) -> AnyView {
        AnyView(ContentView(model: model))
    }

    public var interruptionWarning: String? {
        model.interruptionWarning
    }
}
