import AppKit
import Combine
import DoctorCore
import ServiceManagement
import UniformTypeIdentifiers

@MainActor final class DoctorStore: ObservableObject {
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
    @Published var monitorEnabled = true {
        didSet { UserDefaults.standard.set(monitorEnabled, forKey: "monitorEnabled") }
    }
    @Published var launchAtLogin = false
    private let runner = ProcessRunner()
    private var timer: Timer?
    private var subscriptions = Set<AnyCancellable>()
    private var storageHealthy = true
    private let storageURL: URL

    var selectedApp: WatchedApp? { apps.first { $0.id == selectedID } }

    init() {
        storageURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeviceControlDoctor/watchlist.json")
        if UserDefaults.standard.object(forKey: "monitorEnabled") != nil {
            monitorEnabled = UserDefaults.standard.bool(forKey: "monitorEnabled")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        load()
        selectedID = apps.first?.id
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.monitorEnabled, !self.apps.isEmpty else { return }
                self.refresh()
            }
        }
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
        refresh()
    }

    private func scheduleRefresh(after seconds: UInt64) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard let self, self.monitorEnabled else { return }
            self.refresh()
        }
    }

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
        let help = await runner.run("/usr/bin/tccutil", [])
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
                let command = await runner.run("/usr/bin/tccutil", ["list", "-s", service.rawValue, "-b", initial.bundleID])
                result = command.timedOut ? .init(state: .unknown, detail: "The permission query timed out.") : TCCOutputParser.parseQuery(output: command.output, exitCode: command.exitCode)
            } else {
                result = .init(state: .unavailable, detail: "This Mac does not currently provide permission listing to DeviceControlDoctor.")
            }
            readings.append(.init(service: service, result: result))
        }
        let identity = current == nil ? AppIdentity() : await IdentityInspector().inspect(path: initial.path)
        guard let index = apps.firstIndex(where: { $0.id == id }) else { return }
        let oldIdentity = apps[index].identity
        let identityChanged = oldIdentity.signatureValid != nil && identity.signatureValid != nil &&
            (oldIdentity.requirement != identity.requirement || oldIdentity.signingIdentifier != identity.signingIdentifier || oldIdentity.teamIdentifier != identity.teamIdentifier || oldIdentity.signatureValid != identity.signatureValid)
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
            let help = await runner.run("/usr/bin/tccutil", [])
            var clients = Set<String>()
            var serviceClients: [PermissionService: Set<String>] = [:]
            if TCCOutputParser.supportsListing(help: help.output) {
                for service in PermissionService.allCases {
                    let command = await runner.run("/usr/bin/tccutil", ["list", "-s", service.rawValue])
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
    }

    func setExpected(_ service: PermissionService, enabled: Bool, appID: UUID) {
        guard !isRepairing else { return }
        guard let index = apps.firstIndex(where: { $0.id == appID }) else { return }
        var selected = Set(apps[index].expectedServices)
        if enabled { selected.insert(service) } else { selected.remove(service) }
        apps[index].expectedServices = PermissionService.allCases.filter { selected.contains($0) }
        save()
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
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(service.settingsAnchor)") {
            NSWorkspace.shared.open(url)
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
    func reset(appID: UUID, services: Set<PermissionService>, quitFirst: Bool, reopen: Bool) async -> Bool {
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
        for (service, arguments) in zip(plan.services, plan.arguments) {
            let result = await runner.run("/usr/bin/tccutil", arguments)
            if result.exitCode == 0 && !result.timedOut {
                succeeded.append(service.title)
                addEvent(app, "Reset \(service.title) for \(app.bundleID). User approval is required again.")
            } else {
                let detail = result.timedOut ? "The reset timed out; its outcome is uncertain. Check System Settings." : String(result.output.prefix(600))
                failures.append("\(service.title): \(detail)")
                addEvent(app, "Reset did not report success for \(service.title). \(detail)")
            }
        }
        if let index = apps.firstIndex(where: { $0.id == appID }) { apps[index].functionalTest = nil }
        save()
        isRepairing = false
        if !succeeded.isEmpty {
            if reopen { openApp(app) }
            openSettings(plan.services.first ?? .accessibility)
        }
        notice = (succeeded.isEmpty ? "No reset reported success." : "Reset: \(succeeded.joined(separator: ", ")). Enable \(app.name) again in System Settings, then run a functional test.")
            + (failures.isEmpty ? "" : "\n\n" + failures.joined(separator: "\n"))
        refresh(appID: appID)
        return failures.isEmpty
    }

    func recordTest(appID: UUID, outcome: FunctionalOutcome, note: String) {
        guard !isRepairing, !isChecking else { return }
        guard let index = apps.firstIndex(where: { $0.id == appID }) else { return }
        let app = apps[index]
        apps[index].functionalTest = .init(outcome: outcome, note: String(note.prefix(4000)), appPath: app.path, appVersion: app.version)
        if outcome == .passed { apps[index].lastKnownWorking = Date() }
        addEvent(app, "User-confirmed functional test: \(outcome.rawValue). \(String(note.prefix(250)))")
        save()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin { notice = "Approve DeviceControlDoctor in System Settings → General → Login Items & Extensions." }
        } catch { notice = "Could not change launch at login: \(error.localizedDescription)"; launchAtLogin = SMAppService.mainApp.status == .enabled }
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
        do { try encoder().encode(report).write(to: url, options: .atomic) }
        catch { notice = "Could not export the report: \(error.localizedDescription)" }
    }

    private func addEvent(_ app: WatchedApp, _ message: String) {
        events.insert(.init(appID: app.id, appName: app.name, message: message), at: 0)
        events = Array(events.prefix(200))
    }
    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601; return encoder
    }
    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let data = try decoder.decode(SavedState.self, from: Data(contentsOf: storageURL))
            guard data.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
            apps = data.apps; events = Array(data.events.prefix(200))
            // Functional evidence belongs to a previous session; retain the baseline and history.
            for index in apps.indices { apps[index].functionalTest = nil }
        } catch {
            storageHealthy = false
            notice = "Could not read the saved watch list. The original file will not be overwritten. \(storageURL.path): \(error.localizedDescription)"
        }
    }
    private func save() {
        guard storageHealthy else { return }
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder().encode(SavedState(schemaVersion: 1, apps: apps, events: events)).write(to: storageURL, options: .atomic)
        } catch { notice = "Could not save the watch list: \(error.localizedDescription)" }
    }
}

private struct SavedState: Codable { var schemaVersion: Int; var apps: [WatchedApp]; var events: [DoctorEvent] }
private struct DiagnosticReport: Encodable {
    var generatedAt: Date; var system: String; var scope: String; var capability: String
    var apps: [WatchedApp]; var events: [DoctorEvent]
}
