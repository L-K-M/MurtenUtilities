import Combine
import Foundation
import RepoMenCore

/// User-armed auto-trash, the suite's one exception to "nothing repairs without a
/// click" (PLAN.md, *User-armed automation*): armed per watched folder, off by
/// default, Trash only, re-verified by `Reclaimer` like a manual reclaim, and run
/// only while the suite allows RepoMen background work. It keeps its own schedule
/// here; the background check (`StaleArtifactWatcher`) never acts.
///
/// The provider owns the one instance. Its loop exists only while a folder is
/// armed, and it checks `backgroundWorkAllowed` before every pass and again right
/// before trashing.
@MainActor
final class AutoTrashController: ObservableObject {
    /// Finds the stale items of the given roots, keyed by governing folder; nil
    /// when cancelled. Reads only.
    typealias Collector = @Sendable (_ roots: [WatchedFolder], _ settings: StaleWatchSettings,
                                     _ now: Date) async -> [String: [CleanableItem]]?
    /// Moves items to the Trash, re-verifying each one first.
    typealias Trasher = @Sendable ([CleanableItem]) async -> [Reclaimer.Outcome]

    @Published private(set) var isRunning = false

    private let preferences: Preferences
    private let backgroundWorkAllowed: @MainActor () -> Bool
    private let didTrash: @MainActor () -> Void
    private let collector: Collector
    private let trasher: Trasher
    private let protectedRoots: [String]
    private let now: () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private var loop: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(preferences: Preferences,
         backgroundWorkAllowed: @escaping @MainActor () -> Bool,
         didTrash: @escaping @MainActor () -> Void = {},
         collector: @escaping Collector = AutoTrashController.liveCollector,
         trasher: @escaping Trasher = AutoTrashController.liveTrasher,
         protectedRoots: [String] = ProtectedLocations.current,
         now: @escaping () -> Date = { Date() },
         sleep: @escaping @Sendable (TimeInterval) async throws -> Void = AutoTrashController.liveSleep) {
        self.preferences = preferences
        self.backgroundWorkAllowed = backgroundWorkAllowed
        self.didTrash = didTrash
        self.collector = collector
        self.trasher = trasher
        self.protectedRoots = protectedRoots
        self.now = now
        self.sleep = sleep
    }

    /// Starts following the armed folders: the loop runs while any is armed.
    func start() {
        preferences.$watchedFolders
            .sink { [weak self] folders in self?.reschedule(folders) }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables = []
        loop?.cancel()
        loop = nil
    }

    /// Folders armed and enabled, protected or not, for the menu section and
    /// Settings to show.
    var armedFolders: [WatchedFolder] {
        preferences.watchedFolders.filter { $0.isEnabled && $0.autoTrashArmed }
    }

    /// Whether `folder` is in a privacy-protected location, where auto-trash
    /// cannot run unattended.
    func isProtected(_ folder: WatchedFolder) -> Bool {
        ProtectedLocations.classify(folder.path, roots: protectedRoots) != .allowed
    }

    /// Whether the suite currently lets armed folders run.
    var isAllowedToRun: Bool { backgroundWorkAllowed() }

    /// Disarms every folder: the menu section's off switch.
    func disarmAll() {
        preferences.watchedFolders = preferences.watchedFolders.map {
            var folder = $0
            folder.autoTrashArmed = false
            return folder
        }
    }

    // MARK: Schedule

    private func reschedule(_ folders: [WatchedFolder]) {
        let anyArmed = folders.contains { $0.isEnabled && $0.autoTrashArmed }
        if !anyArmed {
            loop?.cancel()
            loop = nil
        } else if loop == nil {
            loop = Task { [weak self] in await self?.runLoop() }
        }
    }

    private func runLoop() async {
        var earliest = now().addingTimeInterval(AutoTrash.initialDelay)
        while !Task.isCancelled {
            let due = AutoTrash.nextRun(lastRun: preferences.lastWatchRun?.date, earliest: earliest)
            do {
                try await sleep(max(0, due.timeIntervalSince(now())))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            if backgroundWorkAllowed() {
                await runPass()
                // Never sooner than an interval, whatever the pass recorded.
                earliest = now().addingTimeInterval(AutoTrash.interval)
            } else {
                earliest = now().addingTimeInterval(AutoTrash.pausedRetry)
            }
        }
    }

    // MARK: A pass

    /// One pass over the armed folders. Does nothing unless background work is
    /// allowed; stops before trashing if that changed during the scan.
    func runPass() async {
        guard !isRunning, backgroundWorkAllowed() else { return }
        let settings = preferences.watchSettings
        let roots = AutoTrash.runnableFolders(settings.folders, protectedRoots: protectedRoots)
        guard !roots.isEmpty else { return }

        isRunning = true
        defer { isRunning = false }

        let startedAt = now()
        guard let stale = await collector(roots, settings, startedAt), !Task.isCancelled else { return }
        let candidates = AutoTrash.candidates(staleByRoot: stale, armedPaths: Set(roots.map(\.path)))

        var outcomes: [Reclaimer.Outcome] = []
        if !candidates.isEmpty {
            guard backgroundWorkAllowed(), !Task.isCancelled else { return }
            outcomes = await trasher(candidates)
        }
        record(candidates: candidates, outcomes: outcomes, at: now())
    }

    private func record(candidates: [CleanableItem], outcomes: [Reclaimer.Outcome], at date: Date) {
        let record = AutoTrash.record(candidates: candidates, outcomes: outcomes, at: date)
        preferences.lastWatchRun = record
        if !outcomes.isEmpty {
            preferences.autoTrashLog = AutoTrash.appending(AutoTrash.entries(for: outcomes, at: date),
                                                           to: preferences.autoTrashLog)
        }
        if record.reclaimedCount > 0 {
            preferences.lifetimeReclaimedBytes += record.reclaimedBytes
            preferences.lifetimeReclaimedCount += record.reclaimedCount
            didTrash()
        }
        Log.watch.info("auto-trash pass: \(record.candidateCount) candidates, \(record.reclaimedCount) trashed (\(record.reclaimedBytes) bytes), \(record.failureCount) skipped")
    }

    // MARK: Live dependencies

    nonisolated static let liveCollector: Collector = { roots, settings, now in
        await StaleArtifactSurvey.staleItems(
            in: roots, governedBy: settings.folders.filter(\.isEnabled),
            excludedPaths: settings.excludedPaths, enabledKinds: settings.enabledKinds,
            now: now)
    }

    nonisolated static let liveTrasher: Trasher = { items in
        Reclaimer.reclaim(items, method: .trash)
    }

    nonisolated static let liveSleep: @Sendable (TimeInterval) async throws -> Void = { seconds in
        // Capped at a day so the nanosecond count cannot overflow; the loop
        // recomputes the deadline after waking.
        try await Task.sleep(nanoseconds: UInt64(min(seconds, 24 * 3600) * 1_000_000_000))
    }
}
