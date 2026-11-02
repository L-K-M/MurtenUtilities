import AppKit
import Foundation
import HallPassCore
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class HallPassModel {
    /// What the privileged service is doing; quitting interrupts either.
    enum Activity: Equatable {
        case loading
        case applying
    }

    /// Restart-state keys, unchanged from the standalone app. The suite's
    /// per-module defaults domain keeps them from colliding.
    static let restartUptimeKey = "restartRequiredAtUptime"
    static let restartBootTimeKey = "restartRequiredBootTime"

    var snapshot: PreferencesSnapshot?
    var draft = NetworkConfiguration()
    var selectedInterface: NetworkInterface = .wifi
    private(set) var activity: Activity?
    var notice: String?
    var error: String?
    var needsRestart = false
    var lastBackup: URL?
    private(set) var isDemo = false
    private let service: any PreferencesService
    private let defaults: UserDefaults
    /// nil: the standalone app's folder, read and written in place
    /// (docs/architecture.md, Transition from the standalone apps).
    private let backupLocation: URL?

    init(defaults: UserDefaults, service: any PreferencesService = SystemPreferencesService(),
         backupLocation: URL? = nil) {
        self.defaults = defaults
        self.service = service
        self.backupLocation = backupLocation
    }

    var busy: Bool { activity != nil }
    var isLoaded: Bool { snapshot != nil }
    var isDirty: Bool { snapshot.map { $0.configuration != draft } ?? false }
    var networks: [String] { draft[selectedInterface] ?? [] }
    var totalCount: Int { Set((draft.wifi ?? []) + (draft.ethernet ?? [])).count }
    var plan: PreferencePlan? {
        guard let snapshot else { return nil }
        return try? PreferencePlan(baseline: snapshot, desired: draft)
    }
    var validationMessage: String? {
        do { try draft.validate(); return nil } catch { return error.localizedDescription }
    }

    /// Replaces the standalone app's quit and window-close guard: the suite
    /// asks before quitting while this is non-nil.
    var interruptionWarning: String? {
        switch activity {
        case .applying: return "Applying changes"
        case .loading: return "Reading the current exemptions"
        case nil: return isDirty ? "Unsaved changes to local-network exemptions" : nil
        }
    }

    func startDemo() {
        guard !busy, !isLoaded else { return }
        isDemo = true
        draft = .example
        snapshot = try? PreferencesSnapshot(configuration: draft)
        needsRestart = false
        notice = nil
    }

    func leaveDemo() {
        guard isDemo, !busy else { return }
        isDemo = false
        snapshot = nil
        draft = .init()
        notice = nil
        restoreRestartState()
    }

    func load() async {
        guard !busy else { return }
        activity = .loading
        defer { activity = nil }
        do {
            let result = isDemo ? try PreferencesSnapshot(configuration: .example) : try await service.load()
            snapshot = result
            draft = result.configuration
            notice = nil
        } catch { self.error = error.localizedDescription }
    }

    func add(_ notation: String, interfaces: [NetworkInterface]) throws {
        let canonical = try CIDR(notation).notation
        var candidate = draft
        for interface in interfaces {
            var values = candidate[interface] ?? []
            let exists = values.contains { (try? CIDR($0).notation) == canonical }
            if !exists { values.append(canonical) }
            guard values.count <= 512 else { throw ConfigurationError.tooManyNetworks }
            candidate[interface] = values
        }
        draft = candidate
    }

    func remove(_ notation: String) {
        draft[selectedInterface] = networks.filter { $0 != notation }
        if networks.isEmpty { draft[selectedInterface] = nil }
    }

    func discard() {
        if let snapshot { draft = snapshot.configuration }
    }

    func resetDraft() {
        draft = NetworkConfiguration()
        notice = nil
    }

    func save() async {
        guard !busy, isDirty, let snapshot else { return }
        activity = .applying
        defer { activity = nil }
        do {
            let plan = try PreferencePlan(baseline: snapshot, desired: draft)
            if isDemo {
                self.snapshot = try PreferencesSnapshot(configuration: draft)
                notice = nil
                return
            }
            lastBackup = try writeAutomaticBackup(snapshot.configuration)
            let result = try await service.save(plan)
            self.snapshot = result
            draft = result.configuration
            needsRestart = true
            markRestartRequired()
            notice = nil
        } catch {
            if let serviceError = error as? PreferencesServiceError {
                switch serviceError {
                case .rollbackFailed, .verificationFailed:
                    self.snapshot = nil
                    needsRestart = true
                    markRestartRequired()
                default: break
                }
            }
            self.error = error.localizedDescription
        }
    }

    func exportBackup() {
        guard let snapshot else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "HallPass-Backup.json"
        panel.title = "Back Up the Saved Configuration"
        panel.message = "The backup contains the most recently loaded or saved state."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ConfigurationBackup(configuration: snapshot.configuration).encoded().write(to: url, options: .atomic)
            notice = "Backup exported."
        } catch { self.error = error.localizedDescription }
    }

    func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.title = "Open a HallPass Backup as a Draft"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 1_048_576 else { throw ConfigurationError.unsupportedBackup }
            draft = try ConfigurationBackup.decode(Data(contentsOf: url)).configuration
            notice = nil
        } catch { self.error = error.localizedDescription }
    }

    func showBackups() {
        if let lastBackup { NSWorkspace.shared.activateFileViewerSelecting([lastBackup]) }
        else {
            do {
                let url = try backupDirectory()
                NSWorkspace.shared.open(url)
            } catch { self.error = error.localizedDescription }
        }
    }

    func restoreRestartState() {
        guard !isDemo else { return }
        let savedUptime = defaults.double(forKey: Self.restartUptimeKey)
        let savedBoot = defaults.double(forKey: Self.restartBootTimeKey)
        let boot = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        needsRestart = savedUptime > 0 && abs(boot - savedBoot) < 5
    }

    private func markRestartRequired() {
        let uptime = ProcessInfo.processInfo.systemUptime
        defaults.set(uptime, forKey: Self.restartUptimeKey)
        defaults.set(Date().timeIntervalSince1970 - uptime, forKey: Self.restartBootTimeKey)
    }

    /// `~/Library/Application Support/HallPass/Backups`, shared with the
    /// standalone app so neither hides the other's backups.
    static func standardBackupDirectory() throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return root.appendingPathComponent("HallPass/Backups", isDirectory: true)
    }

    private func backupDirectory() throws -> URL {
        let directory = try backupLocation ?? Self.standardBackupDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return directory
    }

    private func writeAutomaticBackup(_ configuration: NetworkConfiguration) throws -> URL {
        let name = "HallPass-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-"))-\(UUID().uuidString.prefix(8)).json"
        let url = try backupDirectory().appendingPathComponent(name)
        try ConfigurationBackup(configuration: configuration).encoded().write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }
}
