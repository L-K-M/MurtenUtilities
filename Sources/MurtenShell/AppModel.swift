import Foundation
import Observation
import SwiftUI
import MurtenCore
import MurtenModuleKit

/// How long a snooze lasts.
public enum SnoozeDuration: CaseIterable, Identifiable, Sendable {
    case oneDay
    case oneWeek

    public var id: Self { self }

    public var interval: TimeInterval {
        switch self {
        case .oneDay: return 24 * 3600
        case .oneWeek: return 7 * 24 * 3600
        }
    }

    public var title: String {
        switch self {
        case .oneDay: return "Snooze for a Day"
        case .oneWeek: return "Snooze for a Week"
        }
    }
}

/// Per-module notification choice from Settings.
public enum NotificationPreference: Sendable {
    case on
    case off
}

/// A non-modal problem the home window shows until dismissed.
public struct ShellDiagnostic: Identifiable, Equatable, Sendable {
    public let id: String
    public let message: String
}

/// The app's state and the only path from views to services. Views read it
/// and call its intents; it owns the suggestion store, the watch coordinator
/// and the module providers.
///
///     providers ──watch──▶ WatchCoordinator ──observation──▶ SuggestionStore
///                                                                │ changes
///     views ◀──suggestions / openRoute── AppModel ◀──────────────┘
///       └──open / snooze / dismiss──▶ AppModel ──▶ store, notifier, panes
@MainActor
@Observable
public final class AppModel {
    /// Minimum time between automatic update checks.
    static let updateCheckInterval: TimeInterval = 24 * 3600
    /// The feed re-reads the store this often so expired snoozes reappear.
    static let feedRefreshInterval: TimeInterval = 5 * 60
    private static let lastUpdateCheckKey = "lastSuiteUpdateCheck"

    public let modules: [SuiteModule]
    public private(set) var suggestions: [Suggestion] = []
    public private(set) var watchHealth: [String: SuggestionLedger.WatchHealth] = [:]
    public private(set) var applicability: [String: Applicability] = [:]
    public private(set) var openRoute: ModuleRoute?
    /// The module the user last left, so focus can return to its tile.
    public private(set) var lastOpenedModuleID: String?
    /// Bumped whenever something outside the window (menu, notification)
    /// asks for the home window to come forward.
    public private(set) var windowRequests = 0
    public private(set) var diagnostics: [ShellDiagnostic] = []
    public private(set) var launchAtLogin: LaunchAtLoginStatus = .disabled
    public private(set) var availableUpdate: SuiteRelease?
    public private(set) var notificationAuthorization: NotificationAuthorization?

    public var settings: SuiteSettings {
        didSet {
            guard settings != oldValue else { return }
            services.settings.save(settings)
            Task { await applyWatchers() }
        }
    }

    @ObservationIgnored private let services: ShellServices
    @ObservationIgnored private let store: SuggestionStore
    @ObservationIgnored private let allowlist: RouteAllowlist
    @ObservationIgnored private var providers: [String: any SuiteModuleProvider] = [:]
    @ObservationIgnored private var moduleDefaults: [String: UserDefaults] = [:]
    @ObservationIgnored private var coordinator: WatchCoordinator?
    @ObservationIgnored private var background: [Task<Void, Never>] = []
    @ObservationIgnored private var started = false

    public init(factories: [ModuleFactory], services: ShellServices,
                modules: [SuiteModule] = ModuleRegistry.all) {
        self.modules = modules
        self.services = services
        self.settings = services.settings.load()

        let known = Set(modules.map(\.id))
        store = SuggestionStore(persistence: services.suggestionPersistence, knownModules: known)

        var built: [String: any SuiteModuleProvider] = [:]
        var defaults: [String: UserDefaults] = [:]
        var actions: [String: [String: Set<String>]] = [:]
        // Providers need callbacks into self; those capture weakly and are
        // only invoked after init completes.
        var weakSelf: () -> AppModel? = { nil }
        for factory in factories where known.contains(factory.moduleID) && built[factory.moduleID] == nil {
            let moduleID = factory.moduleID
            let moduleDefaults = services.moduleDefaults(moduleID)
            let context = ModuleContext(
                moduleID: moduleID, defaults: moduleDefaults,
                requestRecheck: { weakSelf()?.recheck(moduleID) },
                open: { weakSelf()?.open($0) })
            let provider = factory.make(context)
            built[moduleID] = provider
            defaults[moduleID] = moduleDefaults
            actions[moduleID] = provider.routeActions
        }
        allowlist = RouteAllowlist(modules: known, actions: actions)
        providers = built
        moduleDefaults = defaults
        weakSelf = { [weak self] in self }

        let registrations = built.values.compactMap(\.watch)
        coordinator = WatchCoordinator(
            registrations: registrations, clock: services.clock,
            gate: { [weak self] resources in await self?.gate(for: resources) ?? .open },
            sink: { [weak self] observation, registration in await self?.receive(observation, from: registration) })
    }

    // MARK: - Lifecycle

    /// Restores suggestions, checks applicability and starts the watchers
    /// the settings allow. Idempotent.
    public func start() async {
        guard !started else { return }
        started = true

        let outcome = await store.load(at: services.clock.now())
        if case .recovered(let quarantinedAt, _) = outcome {
            let location = quarantinedAt.map { " It was moved to \($0.path)." } ?? ""
            report(ShellDiagnostic(id: "store-recovered",
                                   message: "Saved suggestions could not be read, so the list starts empty.\(location)"))
        }

        launchAtLogin = services.launchAtLogin.status
        services.notifier.onOpen = { [weak self] url in self?.openExternal(url) }
        services.wake.observeWake { [weak self] in self?.systemDidWake() }

        await refreshApplicability()
        observeStore()
        await applyWatchers()
        await checkForUpdatesIfDue()
    }

    /// Stops all background work, e.g. before quitting.
    public func stop() async {
        background.forEach { $0.cancel() }
        background = []
        await coordinator?.setEnabled([])
    }

    // MARK: - Modules

    public func isMigrated(_ moduleID: String) -> Bool {
        providers[moduleID] != nil
    }

    public func module(_ moduleID: String) -> SuiteModule? {
        modules.first { $0.id == moduleID }
    }

    /// Modules with a background check, in home-screen order.
    public var watchedModules: [SuiteModule] {
        modules.filter { providers[$0.id]?.watch != nil }
    }

    /// Modules with a settings tab, in home-screen order.
    public var modulesWithSettings: [SuiteModule] {
        modules.filter { providers[$0.id]?.makeSettings() != nil }
    }

    public func pane(for route: ModuleRoute) -> AnyView? {
        providers[route.moduleID]?.makePane(route: route)
    }

    public func settingsPane(for moduleID: String) -> AnyView? {
        providers[moduleID]?.makeSettings()
    }

    public func defaults(for moduleID: String) -> UserDefaults {
        moduleDefaults[moduleID] ?? .standard
    }

    /// Why quitting now would interrupt work, one line per busy module.
    public func interruptionWarnings() -> [String] {
        modules.compactMap { module in
            providers[module.id]?.interruptionWarning.map { "\(module.name): \($0)" }
        }
    }

    public func refreshApplicability() async {
        for (moduleID, provider) in providers {
            applicability[moduleID] = await provider.applicability()
        }
    }

    // MARK: - Navigation

    public enum OpenOutcome: Equatable, Sendable {
        case opened
        case rejected(String)
    }

    /// Opens a module pane. Routes are validated against each module's
    /// allowlist; planned or inapplicable modules do not open.
    @discardableResult
    public func open(_ route: ModuleRoute) -> OpenOutcome {
        let validated: ModuleRoute
        do {
            validated = try allowlist.validate(route)
        } catch {
            return .rejected("That link is not valid: \(error).")
        }

        guard providers[validated.moduleID] != nil else {
            return .rejected("\(module(validated.moduleID)?.name ?? validated.moduleID) is not available yet.")
        }
        if case .inapplicable(let reason)? = applicability[validated.moduleID] {
            return .rejected(reason)
        }

        openRoute = validated
        lastOpenedModuleID = validated.moduleID
        return .opened
    }

    public func openHome() {
        openRoute = nil
    }

    /// Opens a route from outside the window (menu bar, notification) and
    /// brings the window forward. nil shows the home screen.
    public func present(_ route: ModuleRoute?) {
        if let route {
            if case .rejected(let message) = open(route) {
                report(ShellDiagnostic(id: "route-\(route.moduleID)", message: message))
            }
        } else {
            openHome()
        }
        windowRequests += 1
    }

    /// Handles a `murten://` URL from a notification payload.
    public func openExternal(_ url: URL) {
        do {
            present(try allowlist.route(from: url))
        } catch {
            report(ShellDiagnostic(id: "route-invalid", message: "Ignored an invalid link (\(error))."))
            windowRequests += 1
        }
    }

    // MARK: - Suggestions

    public func snooze(_ suggestion: Suggestion, for duration: SnoozeDuration) async {
        await store.snooze(suggestion.key, until: services.clock.now().addingTimeInterval(duration.interval))
    }

    public func dismiss(_ suggestion: Suggestion) async {
        await store.dismiss(suggestion.key)
    }

    public func recheck(_ moduleID: String) {
        Task { await coordinator?.expedite(moduleID) }
    }

    public func dismissDiagnostic(_ diagnostic: ShellDiagnostic) {
        diagnostics.removeAll { $0.id == diagnostic.id }
    }

    private func report(_ diagnostic: ShellDiagnostic) {
        diagnostics.removeAll { $0.id == diagnostic.id }
        diagnostics.append(diagnostic)
    }

    private func observeStore() {
        let store = self.store
        background.append(Task { [weak self] in
            for await _ in await store.changes() {
                await self?.refreshFeed()
            }
        })
        background.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.feedRefreshInterval * 1_000_000_000))
                await self?.refreshFeed()
            }
        })
    }

    /// Shows suggestions only for watchers that may run: resident mode on,
    /// watcher enabled, module applicable.
    func refreshFeed() async {
        let visible = runnableWatchers()
        let now = services.clock.now()
        suggestions = await store.suggestions(at: now).filter { visible.contains($0.moduleID) }
        watchHealth = await store.health()
    }

    // MARK: - Watchers

    private func runnableWatchers() -> Set<String> {
        let applicable = providers.compactMap { moduleID, provider -> String? in
            guard provider.watch != nil, applicability[moduleID] == .applicable else { return nil }
            return moduleID
        }
        return settings.runnableWatchers(among: Set(applicable))
    }

    func applyWatchers() async {
        await coordinator?.setEnabled(runnableWatchers())
        await refreshFeed()
    }

    private func gate(for resources: WatchResources) async -> WatchGate {
        let environment = await services.environment.sample()
        return settings.gate(for: resources, in: environment)
    }

    private func receive(_ observation: Observation, from registration: WatcherRegistration) async {
        let now = services.clock.now()
        let events = await store.record(observation, rule: registration.rule, at: now)
        let notify = settings.notifyingModules.intersection(runnableWatchers())
        let claimed = await store.claimNotifications(for: events, notifying: notify, at: now)
        for suggestion in claimed {
            services.notifier.deliver(suggestion, moduleName: module(suggestion.moduleID)?.name ?? suggestion.moduleID)
        }
    }

    private func systemDidWake() {
        Task { await coordinator?.systemDidWake() }
    }

    // MARK: - Settings intents

    /// Turning notifications on asks for authorization the first time.
    public func setNotifications(_ preference: NotificationPreference, for moduleID: String) async {
        switch preference {
        case .off:
            settings.notifyingModules.remove(moduleID)
        case .on:
            let authorization = await services.notifier.requestAuthorization()
            notificationAuthorization = authorization
            guard authorization == .granted else { return }
            settings.notifyingModules.insert(moduleID)
        }
    }

    public func setLaunchAtLogin(_ request: LaunchAtLoginRequest) {
        do {
            try services.launchAtLogin.apply(request)
        } catch {
            report(ShellDiagnostic(id: "login-item", message: "Could not change the login item: \(error.localizedDescription)"))
        }
        launchAtLogin = services.launchAtLogin.status
    }

    // MARK: - Suite updates

    /// Checks at most daily, and only when the user turned checks on.
    public func checkForUpdatesIfDue() async {
        guard settings.updateChecks == .daily else { return }

        let now = services.clock.now()
        if let last = services.stateDefaults.object(forKey: Self.lastUpdateCheckKey) as? Date,
           now.timeIntervalSince(last) < Self.updateCheckInterval { return }

        await checkForUpdates()
    }

    public func checkForUpdates() async {
        services.stateDefaults.set(services.clock.now(), forKey: Self.lastUpdateCheckKey)
        do {
            let release = try await services.updates.latestRelease()
            guard let current = services.currentVersion, current < release.version else {
                availableUpdate = nil
                return
            }
            availableUpdate = release
        } catch {
            report(ShellDiagnostic(id: "update-check", message: "Could not check for updates: \(error.localizedDescription)"))
        }
    }
}
