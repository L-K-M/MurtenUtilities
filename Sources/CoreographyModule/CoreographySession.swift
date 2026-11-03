import AppKit
import Observation
import CoreographyKit
import CoreographyServices

/// Everything Coreography keeps while the suite runs: one model for the
/// pane, the menu section and the HUD, as the standalone app had one
/// sampler for every surface. The provider creates it on first use, so a
/// person who never opens Coreography never opens its store or listener.
///
/// Sampling runs only while something shows or uses live readings, the
/// suite's rule for work outside a watcher:
///
///     pane visible ──┐
///     menu visible ──┤
///     HUD shown ─────┼──▶ sampling ──▶ lanes, history, alert tints
///     recording ─────┤
///     MCP client ────┘
///
/// The standalone app sampled from launch to quit, so its history had no
/// gaps while it ran; here history covers the times Coreography was in use.
@MainActor
final class CoreographySession {
    enum Surface: Hashable {
        case pane
        case menu
    }

    /// The standalone app's bundle id, to find its copies: their `coreo`
    /// is the MCP bridge, never the client.
    private static let standaloneBundleID = "ch.lkmc.Coreography"
    /// The standalone app gave quitting three seconds to write history;
    /// here the main thread waits, so less.
    private static let quitGrace: DispatchTimeInterval = .seconds(2)

    let model: DashboardModel
    let hud: HUDController
    let mcpAccess: MCPAccess
    let helperAccess: HelperAccess
    let preferences: UserDefaults

    private let historyRecorder: HistoryRecorder?
    private var visible: Set<Surface> = []
    private var approvalPresenter: MCPApprovalPresenter?
    private var terminationObserver: NSObjectProtocol?

    /// - Parameter showPane: brings Coreography's pane up, e.g. when an MCP
    ///   client waits for approval.
    init(preferences: UserDefaults, showPane: @escaping @MainActor () -> Void) {
        self.preferences = preferences
        let history = HistoryRecorder.makeDefault()
        historyRecorder = history.recorder
        // No notifier: the suite owns notifications. Alerts still tint
        // lanes and mark the timeline while sampling runs.
        let model = DashboardModel(notifier: nil, history: history, preferences: preferences)
        self.model = model
        hud = HUDController(model: model, preferences: preferences)
        helperAccess = HelperAccess()

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let standalone = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: Self.standaloneBundleID).map(\.path)
        mcpAccess = MCPAccess(version: version, snapshot: { model.diagnosticSnapshot() },
                              defaults: preferences, bridgeBundles: standalone)

        hud.onVisibilityChange = { [weak self] in self?.updateSampling() }
        approvalPresenter = MCPApprovalPresenter(access: mcpAccess, present: showPane)
        observeMCPSessions()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.prepareForQuit() }
        }
    }

    // MARK: - Sampling demand

    func appeared(_ surface: Surface) {
        visible.insert(surface)
        updateSampling()
    }

    func disappeared(_ surface: Surface) {
        visible.remove(surface)
        updateSampling()
    }

    /// Whether anything shows or uses live readings right now.
    var needsSampling: Bool {
        !visible.isEmpty || hud.isShown || model.recordingName != nil || !mcpAccess.sessions.isEmpty
    }

    /// Starts sampling when something needs it and stops it otherwise.
    /// Both are idempotent; a person's own pause still wins over `start`.
    func updateSampling() {
        if needsSampling { model.start() } else { model.stop() }
    }

    /// A connected MCP client reads live diagnostics, so it keeps sampling
    /// on; its session ending lets it stop.
    private func observeMCPSessions() {
        withObservationTracking {
            _ = mcpAccess.sessions.isEmpty
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateSampling()
                self?.observeMCPSessions()
            }
        }
    }

    // MARK: - Quitting

    /// The suite owns the app delegate and cannot wait for a module, so the
    /// listener closes and buffered history is written here, with a short
    /// bounded wait instead of the standalone app's delayed termination.
    private func prepareForQuit() {
        mcpAccess.shutdown()
        model.stop()
        guard let recorder = historyRecorder else { return }

        let written = DispatchSemaphore(value: 0)
        Task.detached {
            await recorder.flush()
            written.signal()
        }
        _ = written.wait(timeout: .now() + Self.quitGrace)
    }
}
