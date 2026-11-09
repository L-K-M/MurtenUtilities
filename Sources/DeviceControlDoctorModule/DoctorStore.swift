import AppKit
import Combine
import DoctorCore
import MurtenCore
import UniformTypeIdentifiers

/// The module's long-lived state, owned by the provider so it outlives the
/// pane views. It checks only when asked or while the pane is visible
/// (`monitorWhileVisible()`); background checks are the watcher's job.
@MainActor final class DoctorStore: ObservableObject {
    static let monitorEnabledKey = "monitorEnabled"
    /// Bundle id of the standalone app, which shares the watch list file.
    static let standaloneBundleIdentifier = "ch.lkmc.DeviceControlDoctor"

    @Published var apps: [WatchedApp] = []
    @Published var selectedID: UUID?
    @Published var candidates: [WatchedApp] = []
    @Published var recordedClients: Set<String> = []
    @Published var events: [DoctorEvent] = []
    @Published var isChecking = false
    @Published var isDiscovering = false
    @Published var isRepairing = false
    @Published var queryAvailable: Bool?
    @Published var capabilityDetail = "Permission querying has not been checked yet."
    @Published var lastChecked: Date?
    @Published var notice: String?
    /// Re-check every minute while the pane is visible (the standalone
    /// app's "Check every minute").
    @Published var monitorEnabled = true {
        didSet { defaults.set(monitorEnabled, forKey: Self.monitorEnabledKey) }
    }
    private let defaults: UserDefaults
    private let runner: any ProcessRunning
    private let resetAll: ResetAllPermissions
    private let lifecycle: any ApplicationLifecycleManaging
    private let settingsOpener: @MainActor (URL) -> Void
    /// Tells the suite to re-run the watcher after a change the user made,
    /// so a suggestion that change settled resolves soon.
    private let watchListChanged: @MainActor () -> Void
    private var subscriptions = Set<AnyCancellable>()
    private var visiblePanes = 0
    private var storageHealthy = true
    private let storageURL: URL

    var selectedApp: WatchedApp? { apps.first { $0.id == selectedID } }

    /// Loads the watch list; spawns nothing until a check is asked for.
    init(defaults: UserDefaults, runner: any ProcessRunning = ProcessRunner(),
         storageURL: URL = WatchListFile.defaultURL,
         lifecycle: (any ApplicationLifecycleManaging)? = nil,
         resetTiming: ResetAllPermissions.Timing = .live,
         settingsOpener: (@MainActor (URL) -> Void)? = nil,
         watchListChanged: @escaping @MainActor () -> Void = {}) {
        self.defaults = defaults
        self.runner = runner
        let lifecycle = lifecycle ?? WorkspaceApplicationLifecycle()
        self.lifecycle = lifecycle
        self.resetAll = ResetAllPermissions(runner: runner, lifecycle: lifecycle, timing: resetTiming)
        self.settingsOpener = settingsOpener ?? { _ = NSWorkspace.shared.open($0) }
        self.storageURL = storageURL
        self.watchListChanged = watchListChanged
        if defaults.object(forKey: Self.monitorEnabledKey) != nil {
            monitorEnabled = defaults.bool(forKey: Self.monitorEnabledKey)
        }
        load()
        selectedID = apps.first?.id
    }

    // MARK: - While the pane is visible

    /// The standalone app's monitor, scoped to the pane: one check when the
    /// pane appears, then every minute while it stays visible and monitoring
    /// is on, plus launch and wake follow-ups. Runs until the calling task
    /// (the pane's `.task`) is cancelled.
    func monitorWhileVisible() async {
        visiblePanes += 1
        if visiblePanes == 1 { observeWorkspace() }
        defer {
            visiblePanes -= 1
            if visiblePanes == 0 { subscriptions.removeAll() }
        }

        noteStandaloneApp()
        refresh()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            if monitorEnabled && !apps.isEmpty { refresh() }
        }
    }

    /// Applies a suggestion's route: selects the app it names. It never opens
    /// the repair sheet; the check the pane runs on appearing re-reads it.
    func apply(_ route: ModuleRoute?) {
        guard let appID = DoctorRoute.appID(in: route) else { return }
        guard apps.contains(where: { $0.id == appID }) else {
            notice = "The app from that suggestion is no longer on your watch list."
            return
        }
        selectedID = appID
    }

    private func noteStandaloneApp() {
        guard notice == nil,
              !NSRunningApplication.runningApplications(withBundleIdentifier: Self.standaloneBundleIdentifier).isEmpty else { return }
        notice = "The standalone DeviceControlDoctor app is also running. Both save the same watch list, so quit one of them to keep changes from overwriting each other."
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        center.publisher(for: NSWorkspace.didLaunchApplicationNotification).receive(on: RunLoop.main).sink { [weak self] notification in
            guard let self, let running = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let path = running.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path else { return }
            if let index = self.apps.firstIndex(where: { $0.path == path }) {
                self.apps[index].functionalTest = nil
                self.addEvent(self.apps[index], "App launched. Test the new process to verify functionality.")
                self.save()
                if self.monitorEnabled { self.scheduleRefresh(after: 3) }
            }
        }.store(in: &subscriptions)
        center.publisher(for: NSWorkspace.didTerminateApplicationNotification).receive(on: RunLoop.main).sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        center.publisher(for: NSWorkspace.didWakeNotification).receive(on: RunLoop.main).sink { [weak self] _ in
            if self?.monitorEnabled == true { self?.scheduleRefresh(after: 10) }
        }.store(in: &subscriptions)
    }

    private func scheduleRefresh(after seconds: UInt64) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard let self, self.monitorEnabled, self.visiblePanes > 0 else { return }
            self.refresh()
        }
    }

    // MARK: - Checks

    func refresh() { beginCheck(ids: apps.map(\.id)) }
    func refresh(appID: UUID) { beginCheck(ids: [appID]) }
    private func beginCheck(ids: [UUID]) {
        guard !isChecking, !isRepairing else { return }
        isChecking = true
        Task {
            defer { isChecking = false }
            await checkCapability()
            for id in ids { await checkApp(id) }
            lastChecked = Date()
            save()
        }
    }

    private func checkCapability() async {
        let help = await runner.run(SystemTool.tccutil, [])
        queryAvailable = !help.timedOut && TCCOutputParser.supportsListing(help: help.output)
        capabilityDetail = queryAvailable == true
            ? "This Mac supports tccutil list. Results describe OS-reported authorization, not a functional test."
            : "Permission listing is unavailable here. macOS versions, management policy, or a sandbox can restrict it. Use System Settings and the Test Pad. " + String(help.output.prefix(350))
    }

    private func checkApp(_ id: UUID) async {
        guard let initial = apps.first(where: { $0.id == id }) else { return }
        let current = AppCatalog.app(at: URL(fileURLWithPath: initial.path), clientIdentifier: initial.canReset ? nil : initial.bundleID)
        var readings: [PermissionReading] = []
        for service in PermissionService.allCases {
            let result: AuthorizationResult
            if current == nil {
                result = .init(state: .unavailable, detail: "The application is missing at its saved path. Locate the current copy before repairing.")
            } else if initial.canReset && current?.bundleID != initial.bundleID {
                result = .init(state: .unknown, detail: "The app at this path now has a different bundle identifier. Remove this watch entry and add the current app.")
            } else if queryAvailable == true {
                let command = await runner.run(SystemTool.tccutil, ["list", "-s", service.rawValue, "-b", initial.bundleID])
                result = command.timedOut ? .init(state: .unknown, detail: "The permission query timed out.") : TCCOutputParser.parseQuery(output: command.output, exitCode: command.exitCode)
            } else {
                result = .init(state: .unavailable, detail: "This Mac does not currently provide permission listing to App Permission Checkup.")
            }
            readings.append(.init(service: service, result: result))
        }
        let identity = current == nil ? AppIdentity() : await IdentityInspector(runner: runner).inspect(path: initial.path)
        guard let index = apps.firstIndex(where: { $0.id == id }) else { return }
        // Shared with the watcher, so both judge a change the same way.
        let identityChanged = identity.hasChanged(from: apps[index].identity)
        if current == nil || (initial.canReset && current?.bundleID != initial.bundleID) { apps[index].functionalTest = nil }
        if identityChanged {
            apps[index].identityChangedAt = Date()
            apps[index].functionalTest = nil
            addEvent(initial, "Signing identity or signature validity changed. Previous test evidence was cleared; this does not prove access was lost.")
        }
        if let current, current.version != initial.version {
            apps[index].version = current.version
            apps[index].functionalTest = nil
            addEvent(initial, "Version changed from \(initial.version) to \(current.version). Previous functional evidence is historical.")
        }
        for reading in readings {
            if let old = initial.readings.first(where: { $0.service == reading.service }), old.result.state != reading.result.state {
                apps[index].functionalTest = nil
                addEvent(initial, "\(reading.service.title): \(old.result.state.title) → \(reading.result.state.title).")
            }
        }
        apps[index].readings = readings
        apps[index].identity = identity
    }

    func discoverApps() {
        guard !isDiscovering else { return }
        isDiscovering = true
        Task {
            defer { isDiscovering = false }
            // Separate discovery from refresh: listing has no permission-changing side effects.
            let help = await runner.run(SystemTool.tccutil, [])
            var clients = Set<String>()
            var serviceClients: [PermissionService: Set<String>] = [:]
            if TCCOutputParser.supportsListing(help: help.output) {
                for service in PermissionService.allCases {
                    let command = await runner.run(SystemTool.tccutil, ["list", "-s", service.rawValue])
                    if command.exitCode == 0 && !command.timedOut {
                        let records = Set(TCCOutputParser.parseClients(output: command.output))
                        serviceClients[service] = records
                        clients.formUnion(records)
                    }
                }
            }
            recordedClients = clients
            candidates = AppCatalog.installedApps(recordedClients: clients).map { app in
                var app = app
                app.expectedServices = PermissionService.allCases.filter { serviceClients[$0]?.contains(app.bundleID) == true }
                return app
            }
        }
    }

    func chooseApps() {
        guard !isRepairing else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose apps to watch"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK { addApps(panel.urls.compactMap { AppCatalog.app(at: $0) }) }
    }

    func addApps(_ additions: [WatchedApp]) {
        guard !isRepairing else { return }
        for app in additions where !apps.contains(where: { $0.bundleID == app.bundleID && $0.path == app.path }) {
            apps.append(app)
            addEvent(app, "Added to watch list. Expected permissions can be adjusted for this app.")
        }
        apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if selectedID == nil || !apps.contains(where: { $0.id == selectedID }) { selectedID = apps.first?.id }
        save()
        refresh()
    }

    func removeApp(_ id: UUID) {
        guard !isRepairing else { return }
        apps.removeAll { $0.id == id }
        if selectedID == id { selectedID = apps.first?.id }
        save()
        watchListChanged()
    }

    func setExpected(_ service: PermissionService, enabled: Bool, appID: UUID) {
        guard !isRepairing else { return }
        guard let index = apps.firstIndex(where: { $0.id == appID }) else { return }
        var selected = Set(apps[index].expectedServices)
        if enabled { selected.insert(service) } else { selected.remove(service) }
        apps[index].expectedServices = PermissionService.allCases.filter { selected.contains($0) }
        save()
        watchListChanged()
    }

    func isRunning(_ app: WatchedApp) -> Bool { !matchingProcesses(app).isEmpty }
    private func matchingProcesses(_ app: WatchedApp) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path == app.path }
    }
    func runningPaths(_ app: WatchedApp) -> [String] {
        let paths = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == app.bundleID }.compactMap { $0.bundleURL?.path }
        return Array(Set(paths)).sorted()
    }
    func openSettings(_ service: PermissionService) {
        openSettings(anchor: service.settingsAnchor)
    }

    func openResetSettings(_ service: ResetService) {
        openSettings(anchor: service.settingsAnchor)
    }

    private func openSettings(anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            settingsOpener(url)
        }
    }
    func revealApp(_ app: WatchedApp) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)]) }
    func openApp(_ app: WatchedApp) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: .init()) { [weak self] _, error in
            if let error { Task { @MainActor in self?.notice = error.localizedDescription } }
        }
    }

    func restartApp(_ app: WatchedApp) {
        guard !isChecking, !isRepairing else { return }
        isRepairing = true
        Task {
            let processes = matchingProcesses(app)
            for process in processes { _ = process.terminate() }
            for _ in 0..<50 {
                if processes.allSatisfy(\.isTerminated) { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard processes.allSatisfy(\.isTerminated), matchingProcesses(app).isEmpty else {
                notice = "\(app.name) stayed open. Save any work and quit it normally. No permissions were changed."
                isRepairing = false
                return
            }
            if let index = apps.firstIndex(where: { $0.id == app.id }) { apps[index].functionalTest = nil }
            addEvent(app, "Requested restart without resetting any permissions. Run a functional test after it reopens.")
            save()
            isRepairing = false
            openApp(app)
            notice = "Restarted \(app.name) without resetting permissions. Test the affected feature to check for a startup-timing problem."
            scheduleRefresh(after: 3)
        }
    }

    /// Called only after the repair dialog's explicit confirmation. Never run by monitoring.
    /// Success means the commands reported success, not that effective access
    /// changed: organization policy can remain in force after a local reset.
    func reset(appID: UUID, services: Set<ResetService>, quitFirst: Bool, reopen: Bool) async -> Bool {
        guard !isChecking, !isRepairing, let app = apps.first(where: { $0.id == appID }) else { return false }
        let plan: RepairPlan
        do { plan = try RepairPlan(bundleIdentifier: app.bundleID, services: services) }
        catch { notice = error.localizedDescription; return false }
        guard let current = AppCatalog.app(at: URL(fileURLWithPath: app.path)), current.bundleID == app.bundleID else {
            notice = "The app is missing or its bundle identifier changed. Add the current app before resetting."; return false
        }
        isRepairing = true
        if quitFirst {
            let processes = matchingProcesses(app)
            for process in processes { _ = process.terminate() }
            for _ in 0..<50 {
                if processes.allSatisfy(\.isTerminated) { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if !processes.allSatisfy(\.isTerminated) || !matchingProcesses(app).isEmpty {
                notice = "\(app.name) did not quit. Save any work and quit it normally, then try again. No permissions were reset."
                isRepairing = false; return false
            }
        }
        var succeeded: [String] = []
        var failures: [String] = []
        for outcome in await PermissionReset(runner: runner).apply(plan) {
            let service = outcome.service
            if let detail = outcome.failure {
                failures.append("\(service.title): \(detail)")
                addEvent(app, "Reset did not report success for \(service.title). \(detail)")
            } else {
                succeeded.append(service.title)
                addEvent(app, "tccutil reported a successful \(service.title) reset command for \(app.bundleID). Effective access is unverified; organization (MDM) policy may still apply.")
            }
        }
        if let index = apps.firstIndex(where: { $0.id == appID }) { apps[index].functionalTest = nil }
        save()
        watchListChanged()
        isRepairing = false
        if !succeeded.isEmpty {
            if reopen { openApp(app) }
            openResetSettings(plan.services.first ?? .accessibility)
        }
        notice = (succeeded.isEmpty ? "No reset command reported success." : "tccutil reported successful reset commands for: \(succeeded.joined(separator: ", ")). Effective access has not been verified. Organization (MDM) policy may still allow or deny access. Check System Settings and test the affected feature in \(app.name).")
            + (failures.isEmpty ? "" : "\n\n" + failures.joined(separator: "\n"))
        refresh(appID: appID)
        return failures.isEmpty && succeeded.count == plan.services.count
    }

    /// Reads the complete service-wide client scope for the Reset All sheet.
    /// When the OS cannot provide that scope, the broad repair stays disabled.
    func inspectResetAll(including knownClients: Set<String> = []) async throws -> ResetAllPermissions.Preparation {
        guard !isChecking, !isRepairing else { throw ProcessTerminationError.busy }
        do {
            return try await resetAll.inspect(including: knownClients)
        } catch {
            // Closing the sheet cancels its read-only poll. Do not turn the
            // cancelled subprocess result into a notice in the main pane.
            try Task.checkCancellation()
            if !(error is CancellationError) { notice = error.localizedDescription }
            throw error
        }
    }

    func quitResetAllProcess(_ process: AffectedProcess) throws {
        guard !isChecking, !isRepairing else { throw ProcessTerminationError.busy }
        guard process.canRequestTermination else { throw ProcessTerminationError.unavailable }
        lifecycle.requestTermination(of: [process])
    }

    func forceQuitResetAllProcess(_ process: AffectedProcess) throws {
        guard !isChecking, !isRepairing else { throw ProcessTerminationError.busy }
        guard process.canForceTerminate else { throw ProcessTerminationError.unavailable }
        try lifecycle.forceTerminate(process)
    }

    /// Called only by the Reset All confirmation. The acknowledged override
    /// waives quiescence, not scope, inventory, or command-result checks.
    func resetAllPermissions(policy: ResetAllPermissions.RunningAppsPolicy = .requireClosed,
                             including knownClients: Set<String> = [],
                             progress: @MainActor (ResetAllPermissions.Progress) -> Void = { _ in }) async -> Bool {
        guard !isChecking, !isRepairing else {
            notice = ProcessTerminationError.busy.localizedDescription
            return false
        }
        isRepairing = true
        let result = await resetAll.apply(policy: policy, including: knownClients, progress: progress)

        let attempted = result.outcomes.map(\.service.title)
        let succeeded = result.outcomes.filter { $0.failure == nil }.map(\.service.title)
        if !attempted.isEmpty {
            for index in apps.indices { apps[index].functionalTest = nil }
            let policyDetail = policy == .requireClosed
                ? "All affected apps were required to be closed first."
                : "You acknowledged the risk of resetting while affected apps were running."
            events.insert(.init(appName: "All apps", message:
                "Reset All attempted \(attempted.joined(separator: ", ")). \(policyDetail)"), at: 0)
            events = Array(events.prefix(200))
            save()
            watchListChanged()
        }

        isRepairing = false
        if !attempted.isEmpty {
            openSettings(.accessibility)
            refresh()
        }

        if result.succeeded {
            notice = policy == .requireClosed
                ? "Reset all device-control, input-monitoring, screen-recording, and system-audio recording decisions. Re-enable each app in System Settings before opening it again."
                : "Reset all device-control, input-monitoring, screen-recording, and system-audio recording decisions with the running-app override. Restart affected apps and approve access again in System Settings."
        } else {
            let completed = succeeded.isEmpty ? "" : "\n\nCompleted before stopping: \(succeeded.joined(separator: ", "))."
            notice = (result.failure ?? "Reset All did not complete.") + completed
        }
        return result.succeeded
    }

    func recordTest(appID: UUID, outcome: FunctionalOutcome, note: String) {
        guard !isRepairing, !isChecking else { return }
        guard let index = apps.firstIndex(where: { $0.id == appID }) else { return }
        let app = apps[index]
        apps[index].functionalTest = .init(outcome: outcome, note: String(note.prefix(4000)), appPath: app.path, appVersion: app.version)
        if outcome == .passed { apps[index].lastKnownWorking = Date() }
        addEvent(app, "User-confirmed functional test: \(outcome.rawValue). \(String(note.prefix(250)))")
        save()
        watchListChanged()
    }

    func exportReport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "DeviceControlDoctor-report.json"
        panel.message = "Includes app paths, identifiers, permission readings, and notes. Review before sharing."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let report = DiagnosticReport(generatedAt: Date(), system: ProcessInfo.processInfo.operatingSystemVersionString,
            scope: "OS-reported authorization and user-confirmed functional tests. A recorded grant is not proof of functionality. App paths and notes may be personal.",
            capability: capabilityDetail, apps: apps, events: events)
        do { try WatchListFile.encoder().encode(report).write(to: url, options: .atomic) }
        catch { notice = "Could not export the report: \(error.localizedDescription)" }
    }

    private func addEvent(_ app: WatchedApp, _ message: String) {
        events.insert(.init(appID: app.id, appName: app.name, message: message), at: 0)
        events = Array(events.prefix(200))
    }
    private func load() {
        switch WatchListFile.read(at: storageURL) {
        case .missing:
            return
        case .loaded(let data):
            apps = data.apps; events = Array(data.events.prefix(200))
            // Functional evidence belongs to a previous session; retain the baseline and history.
            for index in apps.indices { apps[index].functionalTest = nil }
        case .unreadable(let error):
            storageHealthy = false
            notice = "Could not read the saved watch list. The original file will not be overwritten. \(storageURL.path): \(error.localizedDescription)"
        }
    }
    private func save() {
        guard storageHealthy else { return }
        do { try WatchListFile.write(apps: apps, events: events, to: storageURL) }
        catch { notice = "Could not save the watch list: \(error.localizedDescription)" }
    }
}

private struct DiagnosticReport: Encodable {
    var generatedAt: Date; var system: String; var scope: String; var capability: String
    var apps: [WatchedApp]; var events: [DoctorEvent]
}
