import Foundation

/// Every recorded privacy decision the module could read, classified.
/// Pure: the module reads the databases and resolves clients, this decides
/// what each entry means.
public struct PermissionInventory: Sendable {
    /// One client's entries, the per-app view's unit.
    public struct ClientGroup: Identifiable, Sendable {
        public let id: String
        public let identifier: String
        public let kind: PermissionRecord.ClientKind
        public let client: ClientStatus
        public let entries: [InventoryEntry]

        /// The entries `tccutil` can reset for this client.
        public var resettableEntries: [InventoryEntry] { entries.filter(\.canReset) }
    }

    public let sources: [DatabaseSource]
    public let entries: [InventoryEntry]
    public let readAt: Date

    public init(sources: [DatabaseSource], resolved: [ResolvedRecord], readAt: Date) {
        self.sources = sources
        self.readAt = readAt
        let lookAlikeNames = Self.lookAlikeNames(resolved)
        entries = resolved
            .map { Self.entry($0, lookAlikeNames: lookAlikeNames) }
            .sorted(by: Self.displayOrder)
    }

    // MARK: - Sources

    public var needsFullDiskAccess: Bool {
        sources.contains { if case .needsFullDiskAccess = $0.reading { return true }; return false }
    }

    /// The per-user database is absent, as on macOS 27.
    public var userDatabaseUnavailable: Bool {
        sources.contains { source in
            guard source.database == .user else { return false }
            if case .missing = source.reading { return true }
            return false
        }
    }

    /// Sources that went unread for a reason the Full Disk Access and
    /// per-user notices do not explain: a failed read, or no system
    /// database at all. Each needs its own warning.
    public var problemSources: [DatabaseSource] {
        sources.filter { source in
            switch source.reading {
            case .read, .needsFullDiskAccess: return false
            case .failed: return true
            case .missing: return source.database == .system
            }
        }
    }

    /// Whether the system database, which holds most decisions, was read.
    public var systemDatabaseRead: Bool {
        sources.contains { source in
            guard source.database == .system else { return false }
            if case .read = source.reading { return true }
            return false
        }
    }

    // MARK: - Views

    public func count(_ filter: InventoryFilter) -> Int {
        entries.filter(filter.includes).count
    }

    /// Every service with at least one entry, in catalog order, then by title.
    public var serviceCounts: [(service: PrivacyService, count: Int)] {
        var counts: [String: Int] = [:]
        for entry in entries { counts[entry.service.identifier, default: 0] += 1 }
        return counts.keys
            .map { PrivacyService.named($0) }
            .sorted(by: Self.serviceOrder)
            .map { ($0, counts[$0.identifier] ?? 0) }
    }

    /// The entries that pass the filter, belong to `service` (nil for any),
    /// and mention `search` in a name, identifier or permission title.
    public func entries(filter: InventoryFilter, service: String? = nil, search: String = "") -> [InventoryEntry] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            guard filter.includes(entry) else { return false }
            if let service, entry.service.identifier != service { return false }
            guard !needle.isEmpty else { return true }
            let haystack = [entry.client.name, entry.record.client, entry.service.title, entry.target?.name ?? "", entry.record.target ?? ""]
            return haystack.contains { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    /// Entries grouped by client, in the order of their first entry.
    public static func groups(_ entries: [InventoryEntry]) -> [ClientGroup] {
        var order: [String] = []
        var grouped: [String: [InventoryEntry]] = [:]
        for entry in entries {
            if grouped[entry.clientKey] == nil { order.append(entry.clientKey) }
            grouped[entry.clientKey, default: []].append(entry)
        }
        return order.compactMap { key in
            guard let entries = grouped[key], let first = entries.first else { return nil }
            return ClientGroup(id: key, identifier: first.record.client, kind: first.record.clientKind,
                               client: first.client, entries: entries)
        }
    }

    // MARK: - Classification

    private static func entry(_ resolved: ResolvedRecord, lookAlikeNames: Set<String>) -> InventoryEntry {
        let record = resolved.record
        let client = resolved.client
        let service = PrivacyService.named(record.service)
        var flags: InventoryEntry.Flags = []

        if client.isSystem {
            flags.insert(.system)
        } else {
            switch client.presence {
            case .missing, .inTrash: flags.insert(.leftover)
            case .offline: flags.insert(.offline)
            case .installed: break
            }
            if resolved.signature == .changed { flags.insert(.broken) }
            if let key = nameKey(client), lookAlikeNames.contains(key) { flags.insert(.lookAlike) }
        }
        if record.isManaged { flags.insert(.managed) }
        if service.risk == .high && record.decision.grantsAccess { flags.insert(.highRisk) }
        if let target = resolved.target, !target.isSystem, target.presence == .missing {
            flags.insert(.missingTarget)
        }

        return InventoryEntry(record: record, service: service, client: client,
                              signature: resolved.signature, target: resolved.target, flags: flags)
    }

    /// Names shared by clients of different apps. An executable inside an
    /// app counts as that app, so a bundle record and a path record of the
    /// same app are not look-alikes; macOS's own clients are left out.
    static func lookAlikeNames(_ resolved: [ResolvedRecord]) -> Set<String> {
        var identities: [String: Set<String>] = [:]
        for item in resolved where !item.client.isSystem {
            guard let key = nameKey(item.client) else { continue }
            identities[key, default: []].insert(item.client.appIdentifier ?? item.record.client)
        }
        return Set(identities.filter { $0.value.count > 1 }.keys)
    }

    /// A name worth comparing: folded for case and accents. A client known
    /// only by its identifier has no name to impersonate.
    static func nameKey(_ client: ClientStatus) -> String? {
        let name = client.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, client.presence != .missing else { return nil }
        return name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    // MARK: - Ordering

    private static let catalogIndex: [String: Int] =
        Dictionary(uniqueKeysWithValues: PrivacyService.known.enumerated().map { ($0.element.identifier, $0.offset) })

    static func serviceOrder(_ a: PrivacyService, _ b: PrivacyService) -> Bool {
        let left = catalogIndex[a.identifier] ?? Int.max, right = catalogIndex[b.identifier] ?? Int.max
        if left != right { return left < right }
        switch a.title.localizedStandardCompare(b.title) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        // Two unknown services can share a derived title; the identifier
        // keeps the order strict.
        case .orderedSame: return a.identifier < b.identifier
        }
    }

    static func displayOrder(_ a: InventoryEntry, _ b: InventoryEntry) -> Bool {
        switch a.client.name.localizedStandardCompare(b.client.name) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: break
        }
        if a.record.client != b.record.client { return a.record.client < b.record.client }
        if a.service != b.service { return serviceOrder(a.service, b.service) }
        if a.record.database != b.record.database { return a.record.database == .system }
        return (a.record.target ?? "") < (b.record.target ?? "")
    }
}
