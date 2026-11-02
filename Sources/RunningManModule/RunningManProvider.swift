import AppKit
import SwiftUI
import MurtenCore
import MurtenModuleKit
import RunningManCore
import RunningManServices

/// RunningMan inside the suite. The provider lives as long as the app and owns the
/// model, so runner actions, creation and stop-after-job requests keep running when
/// the pane closes; the pane, the menu section and the settings tab are views of it.
@MainActor
public final class RunningManProvider: SuiteModuleProvider {
    public let moduleID = RunnerHealthCheck.moduleID
    /// A suggestion opens the pane on one runner; nothing more.
    public let routeActions: [String: Set<String>] = [RunnerOfflineRule.routeAction: [RunnerOfflineRule.runnerContextKey]]
    public let watch: WatcherRegistration?

    let model: AppModel
    private let context: ModuleContext

    public convenience init(context: ModuleContext) {
        self.init(context: context, probe: RunnerHealthProbe())
    }

    /// - Parameter demoMode: the standalone app's fictional preview workspace, for tests.
    init(context: ModuleContext, probe: any RunnerStateProbing, demoMode: Bool = false) {
        self.context = context
        model = AppModel(defaults: context.defaults, demoMode: demoMode)

        let memory = RunnerHealthMemoryStore()
        if !demoMode { model.healthMemory = memory }
        let defaults = UnsafeSendableDefaults(context.defaults)
        watch = WatcherRegistration(
            watcher: RunnerHealthWatcher(probe: probe, memory: memory,
                                         additionalDirectories: { AppModel.importedDirectories(in: defaults.value) }),
            rule: RunnerOfflineRule())

        // Stop-after-job requests restored from the last session need polling to act on.
        model.startMonitoring()
    }

    /// Always applicable: with no runner installed yet, the pane is where you register one.
    public func applicability() async -> Applicability { .applicable }

    public func makePane(route: ModuleRoute?) -> AnyView {
        AnyView(RunningManPane(model: model, route: route) { [weak self] route in self?.handle(route) })
    }

    public func makeSettings() -> AnyView? {
        AnyView(SettingsView().environment(model))
    }

    public func makeMenuSection() -> AnyView? {
        let context = context
        return AnyView(RunnerMenuView { route in context.open(route) }.environment(model))
    }

    public var interruptionWarning: String? {
        model.quitWarning?.message
    }

    /// Applies a route when the pane appears for it. It selects the runner and refreshes;
    /// any start, stop or repair still waits for the user's click in the pane.
    func handle(_ route: ModuleRoute?) {
        guard let route, route.moduleID == moduleID, route.action == RunnerOfflineRule.routeAction else { return }
        model.show(runnerID: route.context[RunnerOfflineRule.runnerContextKey])
    }
}

/// `UserDefaults` is thread-safe, but not annotated `Sendable`; the watcher only reads
/// the imported folders from it.
private struct UnsafeSendableDefaults: @unchecked Sendable {
    let value: UserDefaults

    init(_ value: UserDefaults) {
        self.value = value
    }
}

/// The pane: the standalone app's window content, which reports when it is on screen so
/// RunningMan polls only while someone looks.
struct RunningManPane: View {
    let model: AppModel
    let route: ModuleRoute?
    let handle: @MainActor (ModuleRoute?) -> Void
    @State private var isShown = false
    @State private var isWindowVisible = true

    var body: some View {
        ContentView()
            .environment(model)
            .background(WindowOcclusionReader { isWindowVisible = $0 })
            .onAppear {
                isShown = true
                model.paneVisible = isWindowVisible
                handle(route)
            }
            .onDisappear {
                isShown = false
                model.paneVisible = false
            }
            .onChange(of: isWindowVisible) { _, visible in
                if isShown { model.paneVisible = visible }
            }
    }
}

/// Reports whether the hosting window is on screen: not minimised, hidden, on another
/// Space or fully covered.
private struct WindowOcclusionReader: NSViewRepresentable {
    let changed: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.changed = changed
        return view
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {
        nsView.changed = changed
    }

    final class ReaderView: NSView {
        var changed: (@MainActor (Bool) -> Void)?
        /// Touched from `deinit`; NotificationCenter is thread-safe.
        nonisolated(unsafe) private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.report() }
            }
            report()
        }

        private func report() {
            guard let window else { return }
            changed?(window.occlusionState.contains(.visible))
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
