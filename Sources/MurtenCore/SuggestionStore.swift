import Foundation

/// Where the ledger is kept between launches.
public protocol SuggestionPersisting: Sendable {
    /// The saved ledger, or nil when nothing was saved yet. Throws when a
    /// file exists but cannot be read or decoded.
    func load() throws -> SuggestionLedger?
    func save(_ ledger: SuggestionLedger) throws
    /// Moves an unreadable file aside so a fresh ledger does not overwrite
    /// it; returns where it went, or nil when there was nothing to move.
    func quarantine() throws -> URL?
}

/// The single serialized owner of the suggestion ledger. Watcher results,
/// user actions and surfaces all go through it; every change is persisted.
public actor SuggestionStore {
    public enum LoadOutcome: Equatable, Sendable {
        case empty
        case restored(records: Int)
        /// The saved file was unreadable; it was moved aside and the store
        /// started empty. Shown as a diagnostic, never silently.
        case recovered(quarantinedAt: URL?, reason: String)
    }

    private var ledger = SuggestionLedger()
    private let persistence: any SuggestionPersisting
    private let knownModules: Set<String>
    private let retention: RetentionPolicy
    private let throttle: NotificationThrottle
    private var changeObservers: [UUID: AsyncStream<Void>.Continuation] = [:]

    /// The last save failure, if any. The store keeps working in memory.
    public private(set) var persistenceError: String?
    /// Set when an unreadable file could not be moved aside: saving would
    /// overwrite it, so the store stays in memory for this session.
    private var savingSuspended = false

    public init(persistence: any SuggestionPersisting, knownModules: Set<String>,
                retention: RetentionPolicy = .standard, throttle: NotificationThrottle = .standard) {
        self.persistence = persistence
        self.knownModules = knownModules
        self.retention = retention
        self.throttle = throttle
    }

    // MARK: - Lifecycle

    /// Restores the saved ledger. Restoring never produces events, so old
    /// episodes are never re-notified at startup.
    public func load(at now: Date) -> LoadOutcome {
        let outcome: LoadOutcome
        do {
            guard let saved = try persistence.load() else { return .empty }
            ledger = saved
            outcome = .restored(records: saved.records.count)
        } catch {
            ledger = SuggestionLedger()
            do {
                let quarantined = try persistence.quarantine()
                outcome = .recovered(quarantinedAt: quarantined, reason: String(describing: error))
            } catch let moveError {
                savingSuspended = true
                persistenceError = "The unreadable suggestions file could not be moved aside (\(moveError)); changes are not saved."
                outcome = .recovered(quarantinedAt: nil, reason: String(describing: error))
            }
        }

        ledger.prune(at: now, policy: retention, throttle: throttle, knownModules: knownModules)
        persist()
        notifyObservers()
        return outcome
    }

    // MARK: - Observations

    /// Records a watcher result and returns the ledger events it caused.
    @discardableResult
    public func record(_ observation: WatchObservation, rule: any SuggestionRule, at now: Date) -> [SuggestionLedger.Event] {
        guard knownModules.contains(observation.moduleID) else { return [] }

        let events = ledger.apply(observation, rule: rule)
        ledger.prune(at: now, policy: retention, throttle: throttle, knownModules: knownModules)
        persist()
        notifyObservers()
        return events
    }

    /// The suggestions to notify about for these events: newly opened
    /// episodes of modules the user opted into, within the throttle.
    public func claimNotifications(for events: [SuggestionLedger.Event], notifying modules: Set<String>,
                                   at now: Date) -> [Suggestion] {
        let opened = events.compactMap { event -> SuggestionKey? in
            guard case .opened(let key) = event, modules.contains(key.moduleID) else { return nil }
            return key
        }
        let claimed = opened.filter { ledger.claimNotification(for: $0, at: now, throttle: throttle) }
        guard !claimed.isEmpty else { return [] }

        persist()
        let visible = ledger.suggestions(at: now)
        return claimed.compactMap { key in visible.first { $0.key == key } }
    }

    // MARK: - User actions

    public func snooze(_ key: SuggestionKey, until date: Date) {
        guard ledger.snooze(key, until: date) else { return }
        persist()
        notifyObservers()
    }

    public func dismiss(_ key: SuggestionKey) {
        guard ledger.dismiss(key) else { return }
        persist()
        notifyObservers()
    }

    // MARK: - Surfaces

    public func suggestions(at now: Date) -> [Suggestion] {
        ledger.suggestions(at: now)
    }

    public func health() -> [String: SuggestionLedger.WatchHealth] {
        ledger.health
    }

    /// Yields whenever the ledger changes; consumers re-query.
    public func changes() -> AsyncStream<Void> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        changeObservers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    private func removeObserver(_ id: UUID) {
        changeObservers[id] = nil
    }

    private func notifyObservers() {
        for continuation in changeObservers.values { continuation.yield() }
    }

    private func persist() {
        guard !savingSuspended else { return }
        do {
            try persistence.save(ledger)
            persistenceError = nil
        } catch {
            persistenceError = String(describing: error)
        }
    }
}

/// Persists the ledger as versioned JSON, by default at
/// `~/Library/Application Support/MurtenUtilities/suggestions.json`.
public struct JSONFileSuggestionPersistence: SuggestionPersisting {
    public static let formatVersion = 1
    public static let directoryName = "MurtenUtilities"
    public static let fileName = "suggestions.json"

    public enum FormatError: Error, Equatable {
        case unsupportedVersion(Int)
    }

    private struct Envelope: Codable {
        let version: Int
        let ledger: SuggestionLedger
    }

    private struct VersionProbe: Decodable {
        let version: Int
    }

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The standard location in the user's Application Support directory.
    public static func standard(fileManager: FileManager = .default) throws -> JSONFileSuggestionPersistence {
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                          appropriateFor: nil, create: false)
        let url = support.appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
        return JSONFileSuggestionPersistence(fileURL: url)
    }

    public func load() throws -> SuggestionLedger? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let data = try Data(contentsOf: fileURL)
        let decoder = Self.decoder()
        let version = try decoder.decode(VersionProbe.self, from: data).version
        guard version == Self.formatVersion else { throw FormatError.unsupportedVersion(version) }
        return try decoder.decode(Envelope.self, from: data).ledger
    }

    public func save(_ ledger: SuggestionLedger) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Envelope(version: Self.formatVersion, ledger: ledger))
        try data.write(to: fileURL, options: .atomic)
    }

    public func quarantine() throws -> URL? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        // Timestamp for people, UUID so two recoveries never collide.
        let stamp = Int(Date().timeIntervalSince1970)
        let destination = fileURL.deletingLastPathComponent()
            .appendingPathComponent("suggestions.unreadable-\(stamp)-\(UUID().uuidString.prefix(8)).json")
        try FileManager.default.moveItem(at: fileURL, to: destination)
        return destination
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
