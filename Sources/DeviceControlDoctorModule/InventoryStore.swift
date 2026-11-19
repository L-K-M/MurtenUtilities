import AppKit
import Combine
import DoctorCore

/// The All permissions view's state: every recorded privacy decision on
/// this Mac, read on demand from the privacy databases. Owned by the
/// provider beside `DoctorStore`, whose repair lock its resets take.
///
/// It reads only when the view asks (opening it, Refresh); it never polls
/// and the watcher never uses it. Resets need the user's confirmation in
/// the reset sheet and go through `tccutil`, one app and service at a time.
@MainActor final class InventoryStore: ObservableObject {
    /// What the sidebar selects.
    enum Selection: Hashable {
        case filter(InventoryFilter)
        case service(String)
    }

    @Published private(set) var inventory: PermissionInventory?
    @Published private(set) var isReading = false
    @Published private(set) var isResetting = false
    @Published var selection: Selection = .filter(.all)
    @Published var search = ""
    @Published var notice: String?

    private let reader: any PrivacyDatabaseReading
    private let resolver: any ClientResolving
    private let runner: any ProcessRunning
    private let doctor: DoctorStore
    /// Writes the report; false when the pasteboard refused it.
    private let copyToPasteboard: @MainActor (String) -> Bool
    private let systemDescription: String
    private let now: @Sendable () -> Date

    init(doctor: DoctorStore,
         reader: any PrivacyDatabaseReading = TCCDatabaseReader(),
         resolver: any ClientResolving = ClientResolver(),
         runner: any ProcessRunning = ProcessRunner(),
         copyToPasteboard: (@MainActor (String) -> Bool)? = nil,
         systemDescription: String = "macOS " + ProcessInfo.processInfo.operatingSystemVersionString,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.doctor = doctor
        self.reader = reader
        self.resolver = resolver
        self.runner = runner
        self.copyToPasteboard = copyToPasteboard ?? { text in
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString(text, forType: .string)
        }
        self.systemDescription = systemDescription
        self.now = now
    }

    // MARK: - Views

    /// The entries the sidebar selection and the search leave.
    var visibleEntries: [InventoryEntry] {
        guard let inventory else { return [] }
        switch selection {
        case .filter(let filter): return inventory.entries(filter: filter, search: search)
        case .service(let service): return inventory.entries(filter: .all, service: service, search: search)
        }
    }

    var visibleGroups: [PermissionInventory.ClientGroup] { PermissionInventory.groups(visibleEntries) }

    var selectionTitle: String {
        switch selection {
        case .filter(let filter): return filter.title
        case .service(let service): return PrivacyService.named(service).title
        }
    }

    var leftovers: [InventoryEntry] { inventory?.entries(filter: .leftovers) ?? [] }

    // MARK: - Reading

    /// Reads both databases and resolves every client, off the main actor.
    func refresh() async {
        guard !isReading else { return }
        isReading = true
        defer { isReading = false }
        inventory = await read()
        if case .service(let service) = selection,
           inventory?.entries.contains(where: { $0.service.identifier == service }) != true {
            selection = .filter(.all)
        }
    }

    private func read() async -> PermissionInventory {
        let reader = self.reader, resolver = self.resolver, readAt = now()
        return await Task.detached(priority: .userInitiated) {
            let sources = PermissionRecord.Database.allCases.map { DatabaseSource(database: $0, reading: reader.read($0)) }
            let resolved = await resolver.resolve(sources.flatMap(\.reading.records))
            return PermissionInventory(sources: sources, resolved: resolved, readAt: readAt)
        }.value
    }

    // MARK: - Resets

    /// Called only by the reset sheet's confirmation. Runs `tccutil reset
    /// SERVICE BUNDLE_ID` for each resettable entry, then reads the
    /// databases again to judge each one. nil when another check or repair
    /// holds the module's lock.
    func reset(_ entries: [InventoryEntry]) async -> InventoryResetResult? {
        guard !isResetting, !isReading else { return nil }
        guard doctor.beginInventoryReset() else { return nil }
        isResetting = true
        let (plans, skipped) = InventoryResetPlan.plans(for: entries)
        let outcomes = await PermissionReset(runner: runner).apply(plans)
        let requested = entries.filter { entry in !skipped.contains { $0.id == entry.id } }

        isReading = true
        let after = await read()
        isReading = false
        inventory = after

        let result = InventoryResetResult.assess(requested: requested, skipped: skipped,
                                                 commandFailures: outcomes.failures, uncertainCommands: outcomes.uncertain,
                                                 after: after)
        isResetting = false
        // Only apps whose decisions may have changed lose their test evidence.
        doctor.endInventoryReset(resetBundles: outcomes.possiblyReset(plans))
        notice = result.summary
        return result
    }

    // MARK: - Report and Settings

    func copyReport() {
        guard let inventory else { return }
        guard copyToPasteboard(InventoryReport.text(inventory, system: systemDescription)) else {
            notice = "The report could not be put on the clipboard. Try Copy Report again."
            return
        }
        notice = "Copied a report of \(inventory.entries.count) entries. It names your apps, their identifiers and paths; review it before you share it."
    }

    func openSettings(_ service: PrivacyService) {
        doctor.openSettings(anchor: service.settingsAnchor ?? PrivacyService.privacyAnchor)
    }

    func openSettings(anchor: String) {
        doctor.openSettings(anchor: anchor)
    }

    func openFullDiskAccessSettings() {
        doctor.openSettings(anchor: PrivacyService.named("kTCCServiceSystemPolicyAllFiles").settingsAnchor ?? PrivacyService.privacyAnchor)
    }
}
