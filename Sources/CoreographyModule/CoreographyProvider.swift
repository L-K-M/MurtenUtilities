import AppKit
import SwiftUI
import MurtenCore
import MurtenModuleKit
import CoreographyCore
import CoreographyServices

/// Coreography inside Murten Utilities: the monitor window as a pane, its
/// menu-bar extra as a companion section, its alerts as a background check.
///
/// The provider lives as long as the app; the session behind every surface
/// is created on first use (the pane, the menu section, Settings), or at
/// launch when MCP access was left on, as the standalone app listened from
/// launch.
@MainActor
public final class CoreographyProvider: SuiteModuleProvider {
    public let moduleID = CoreographyWatch.moduleID
    public let watch: WatcherRegistration?
    public var routeActions: [String: Set<String>] { CoreographyWatch.routeActions }

    private let context: ModuleContext
    private let sessions: SessionSlot

    public convenience init(context: ModuleContext) {
        self.init(context: context, observer: LiveSystemObserver())
    }

    /// - Parameter observer: what the watcher reads; tests pass fixtures.
    init(context: ModuleContext, observer: any SystemObserving) {
        self.context = context
        watch = WatcherRegistration(watcher: CoreographyWatcher(observer: observer), rule: CoreographyRule())
        let open = context.open
        sessions = SessionSlot {
            CoreographySession(preferences: context.defaults) {
                open(ModuleRoute(moduleID: CoreographyWatch.moduleID))
            }
        }
        if MCPAccess.isEnabled(in: context.defaults) { _ = sessions.session }
    }

    public func makePane(route: ModuleRoute?) -> AnyView {
        AnyView(CoreographyPane(session: sessions.session, route: route))
    }

    public func makeSettings() -> AnyView? {
        AnyView(SessionView(slot: sessions) { session in
            SettingsView(model: session.model, mcpAccess: session.mcpAccess, hud: session.hud,
                         helperAccess: session.helperAccess)
        })
    }

    public func makeMenuSection() -> AnyView? {
        let open = context.open
        return AnyView(SessionView(slot: sessions) { session in
            CoreographyMenuSection(session: session) {
                open(ModuleRoute(moduleID: CoreographyWatch.moduleID))
                NSApplication.shared.activate()
            }
        })
    }

    /// A recording keeps sampling with the window closed; quitting ends it
    /// unsaved, so the shell asks first.
    public var interruptionWarning: String? {
        guard let name = sessions.existing?.model.recordingName else { return nil }
        return name.isEmpty ? "A recording is still running." : "The recording \"\(name)\" is still running."
    }

    /// Whether the session exists yet; for tests.
    var hasSession: Bool { sessions.existing != nil }
}

/// Holds the session once something needs it. The shell asks for menu
/// sections and settings tabs just to learn whether a module has one, so
/// building those views must not create the session; showing them does.
@MainActor
final class SessionSlot {
    private let make: @MainActor () -> CoreographySession
    private(set) var existing: CoreographySession?

    init(make: @escaping @MainActor () -> CoreographySession) {
        self.make = make
    }

    var session: CoreographySession {
        if let existing { return existing }
        let made = make()
        existing = made
        return made
    }
}

/// Resolves the session when SwiftUI evaluates the body, i.e. when the view
/// is actually shown.
private struct SessionView<Content: View>: View {
    let slot: SessionSlot
    @ViewBuilder let content: (CoreographySession) -> Content

    var body: some View {
        content(slot.session)
    }
}
