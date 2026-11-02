import SwiftUI
import DoctorCore
import MurtenCore
import MurtenModuleKit

/// DeviceControlDoctor as a suite module. The provider owns the store, so a
/// check, a selection or a reset outlives the pane views; the shell owns the
/// window, menus, menu bar, login item and notifications.
///
/// - Pane: the standalone app's main window. It checks when it appears and
///   every minute while visible; a suggestion's route only selects an app.
/// - Watcher: `PermissionWatcher` with `VerificationRule`, observation only.
/// - Window "test-pad": the Test Pad. Settings: monitoring and privacy.
/// - Menu section: the standalone app's menu-bar extra.
@MainActor
public final class DeviceControlDoctorProvider: SuiteModuleProvider {
    /// For the executable's module catalog.
    public nonisolated static var factory: ModuleFactory {
        ModuleFactory(moduleID: DoctorRoute.moduleID) { DeviceControlDoctorProvider(context: $0) }
    }

    public let moduleID = DoctorRoute.moduleID
    public let routeActions = DoctorRoute.actions
    public let watch: WatcherRegistration?
    let store: DoctorStore

    public convenience init(context: ModuleContext) {
        self.init(context: context, runner: ProcessRunner(), watchList: WatchListFile.defaultURL)
    }

    /// The pane and the watcher share one process boundary and one watch
    /// list file; tests pass a fake runner and a fixture file.
    init(context: ModuleContext, runner: any ProcessRunning, watchList: URL,
         home: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        store = DoctorStore(defaults: context.defaults, runner: runner, storageURL: watchList,
                            watchListChanged: context.requestRecheck)
        watch = WatcherRegistration(watcher: PermissionWatcher(watchList: watchList, runner: runner, home: home),
                                    rule: VerificationRule())
    }

    public func makePane(route: ModuleRoute?) -> AnyView {
        AnyView(MainView(route: route).environmentObject(store))
    }

    public func makeSettings() -> AnyView? {
        AnyView(SettingsView().environmentObject(store))
    }

    public func makeWindow(_ request: ModuleWindowRequest) -> AnyView? {
        guard request.moduleID == moduleID, request.kind == ModuleWindowRequest.testPad.kind else { return nil }
        return AnyView(TestPadView().environmentObject(store))
    }

    public func makeMenuSection() -> AnyView? {
        AnyView(DoctorMenuSection().environmentObject(store))
    }

    public var interruptionWarning: String? {
        store.isRepairing ? "A permission reset or app restart is still in progress." : nil
    }
}

extension ModuleWindowRequest {
    /// The Test Pad, the standalone app's second window.
    static let testPad = ModuleWindowRequest(moduleID: DoctorRoute.moduleID, kind: "test-pad")
}
