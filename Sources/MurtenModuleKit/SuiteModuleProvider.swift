import SwiftUI
import MurtenCore

/// What the suite hands a module when it creates it. Everything a module
/// needs from the shell goes through here, so modules never reach into the
/// app's globals.
@MainActor
public struct ModuleContext {
    public let moduleID: String
    /// Module-scoped preferences. Keys never collide with another module's;
    /// the shell also installs these as the pane's `@AppStorage` store.
    public let defaults: UserDefaults
    /// Re-runs the module's watcher soon, e.g. after a repair, so a
    /// suggestion the repair fixed resolves without waiting a full interval.
    public let requestRecheck: @MainActor () -> Void
    /// Opens a pane, this module's or another's. Routes are validated
    /// against the allowlist before anything opens.
    public let open: @MainActor (ModuleRoute) -> Void
    /// Whether the user currently allows this module to work in the
    /// background: resident mode on and the module's background check not
    /// switched off. User-armed automation (RepoMen's auto-trash) runs only
    /// while this is true.
    public let backgroundWorkAllowed: @MainActor () -> Bool

    public init(moduleID: String, defaults: UserDefaults,
                requestRecheck: @escaping @MainActor () -> Void, open: @escaping @MainActor (ModuleRoute) -> Void,
                backgroundWorkAllowed: @escaping @MainActor () -> Bool = { false }) {
        self.moduleID = moduleID
        self.defaults = defaults
        self.requestRecheck = requestRecheck
        self.open = open
        self.backgroundWorkAllowed = backgroundWorkAllowed
    }
}

/// A migrated tool as the suite sees it. The shell creates one provider per
/// module at launch and keeps it for the app's lifetime, so long-lived state
/// (a scan, a selection, a running cleanup) belongs in the provider, not in
/// the pane view, which is rebuilt whenever the user navigates.
///
/// Rules every provider follows (docs/architecture.md):
/// - The watcher observes only: no writes, no privilege, no prompts.
/// - A route opens the pane; it never starts a repair. The pane re-scans and
///   asks for explicit confirmation of the current targets.
/// - App-global state stays the shell's: no `NSApp.mainMenu`, activation
///   policy, application delegate, `MenuBarExtra`, login item, notification
///   or update check of the module's own.
@MainActor
public protocol SuiteModuleProvider: AnyObject {
    /// Matches a `ModuleRegistry` descriptor id.
    var moduleID: String { get }

    /// Actions a route may name, each with the context keys it accepts.
    /// Example: `["reclaim": ["endpoint"]]`. Empty: only the bare route.
    var routeActions: [String: Set<String>] { get }

    /// The background check and its rule, or nil for an on-demand module.
    var watch: WatcherRegistration? { get }

    /// A cheap, prompt-free check of whether the module can work here.
    func applicability() async -> Applicability

    /// The module's pane. `route` carries the action and context of the
    /// suggestion or link that opened it; nil for a plain tile click.
    func makePane(route: ModuleRoute?) -> AnyView

    /// The module's own settings tab, or nil when it has none.
    func makeSettings() -> AnyView?

    /// Content for an auxiliary window the pane opened with
    /// `openWindow(module:)`; nil for an unknown kind.
    func makeWindow(_ request: ModuleWindowRequest) -> AnyView?

    /// A compact section for the menu-bar companion: live instruments
    /// (Coreography) or what the module does on its own (RepoMen's armed
    /// auto-trash). nil when the module has nothing to show there.
    func makeMenuSection() -> AnyView?

    /// Non-nil while quitting would interrupt work, e.g. "A cleanup is still
    /// running." The shell asks before quitting.
    var interruptionWarning: String? { get }
}

public extension SuiteModuleProvider {
    var routeActions: [String: Set<String>] { [:] }
    var watch: WatcherRegistration? { nil }
    func applicability() async -> Applicability { .applicable }
    func makeSettings() -> AnyView? { nil }
    func makeWindow(_ request: ModuleWindowRequest) -> AnyView? { nil }
    func makeMenuSection() -> AnyView? { nil }
    var interruptionWarning: String? { nil }
}

/// How the executable registers a module without the shell depending on it.
public struct ModuleFactory {
    public let moduleID: String
    public let make: @MainActor (ModuleContext) -> any SuiteModuleProvider

    public init(moduleID: String, make: @escaping @MainActor (ModuleContext) -> any SuiteModuleProvider) {
        self.moduleID = moduleID
        self.make = make
    }
}
