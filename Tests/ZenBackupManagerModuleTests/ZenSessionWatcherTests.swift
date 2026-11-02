import XCTest
import MurtenCore
@testable import ZenBackupManagerCore
@testable import ZenBackupManagerModule

/// A source that answers from memory, so failures can be staged.
private final class FakeSource: SessionSnapshotSource, @unchecked Sendable {
    private let lock = NSLock()
    private var listed: [ZenProfile] = []
    private var listFailure: Error?
    private var dates: [String: Date] = [:]
    private var failing: Set<String> = []
    private var unreadable: Set<String> = []

    /// `unreadable`: directories profiles.ini names that discovery skipped.
    func set(_ profiles: [ZenProfile], dates: [String: Date] = [:], failing: Set<String> = [],
             unreadable: Set<String> = [], listFailure: Error? = nil) {
        lock.lock(); defer { lock.unlock() }
        listed = profiles
        self.dates = dates
        self.failing = failing
        self.unreadable = unreadable
        self.listFailure = listFailure
    }

    func listedProfileDirectories() throws -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        if let listFailure { throw listFailure }
        return Set(listed.map(\.id)).union(unreadable)
    }

    func profiles() throws -> [ZenProfile] {
        lock.lock(); defer { lock.unlock() }
        if let listFailure { throw listFailure }
        return listed
    }

    func newestSnapshot(in profile: ZenProfile) throws -> Date? {
        lock.lock(); defer { lock.unlock() }
        if failing.contains(profile.id) { throw BackupError.unsafePath }
        return dates[profile.id]
    }
}

final class ZenSessionWatcherTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let work = ZenProfile(name: "Work", directory: URL(fileURLWithPath: "/zen/Profiles/work"), isDefault: true)
    private let home = ZenProfile(name: "Home", directory: URL(fileURLWithPath: "/zen/Profiles/home"), isDefault: false)
    private let day: TimeInterval = 24 * 3600

    private func watcher(_ source: FakeSource) -> ZenSessionWatcher {
        let now = self.now
        return ZenSessionWatcher(source: source, now: { now })
    }

    func testCadenceIsRareAndLocal() {
        let cadence = watcher(FakeSource()).cadence
        XCTAssertGreaterThanOrEqual(cadence.interval, WatchCadence.minimumInterval)
        XCTAssertFalse(cadence.resources.contains(.network))
    }

    func testReportsEveryProfileItChecked() async {
        let source = FakeSource()
        source.set([work, home], dates: [work.id: now.addingTimeInterval(-9 * day)])

        let observation = await watcher(source).observe()

        XCTAssertEqual(observation.outcome, .complete)
        XCTAssertEqual(observation.completedScopes, [FindingScope(work.id), FindingScope(home.id)])
        XCTAssertEqual(observation.findings.count, 1, "a profile without snapshots is checked and quiet")
        XCTAssertEqual(observation.findings.first?.scope, FindingScope(work.id))
        XCTAssertEqual(observation.findings.first?.seconds("age"), 9 * day)
    }

    func testAnUnreadableProfileIsAFailureForThatProfileOnly() async {
        let source = FakeSource()
        source.set([work, home], dates: [home.id: now], failing: [work.id])

        let observation = await watcher(source).observe()

        XCTAssertEqual(observation.outcome, .partial)
        XCTAssertEqual(observation.completedScopes, [FindingScope(home.id)])
        XCTAssertEqual(observation.failures.map(\.scope), [FindingScope(work.id)])
    }

    func testAnUnreadableProfileListMakesTheCheckUnavailable() async {
        let source = FakeSource()
        source.set([], listFailure: CocoaError(.fileReadCorruptFile))

        let observation = await watcher(source).observe()

        XCTAssertEqual(observation.outcome, .unavailable)
        XCTAssertNil(observation.failures.first?.scope)
    }

    func testAProfileThatLeftZensListResolves() async throws {
        let source = FakeSource()
        source.set([work, home], dates: [work.id: now.addingTimeInterval(-9 * day), home.id: now.addingTimeInterval(-9 * day)])
        let rule = SessionStalenessRule()
        var ledger = SuggestionLedger()
        let first = await watcher(source).observe()
        let departed = try XCTUnwrap(first.findings.first { $0.scope == FindingScope(work.id) }?.key)
        XCTAssertTrue(ledger.apply(first, rule: rule).contains(.opened(departed)), "the profile's suggestion is active")

        // A fresh watcher is the relaunch case: nothing remembers the profile.
        source.set([home], dates: [home.id: now.addingTimeInterval(-9 * day)])
        let second = await watcher(source).observe()

        XCTAssertEqual(second.coverage, .exhaustive)
        XCTAssertFalse(second.completedScopes.contains(FindingScope(work.id)), "the scope is absent, not completed")
        XCTAssertFalse(second.findings.contains { $0.scope == FindingScope(work.id) })
        XCTAssertTrue(ledger.apply(second, rule: rule).contains(.resolved(departed)))
    }

    func testAnUnreadableListedProfileGoesStaleNotResolved() async throws {
        let source = FakeSource()
        source.set([work], dates: [work.id: now.addingTimeInterval(-9 * day)])
        let rule = SessionStalenessRule()
        var ledger = SuggestionLedger()
        let first = await watcher(source).observe()
        let key = try XCTUnwrap(first.findings.first?.key)
        ledger.apply(first, rule: rule)

        // profiles.ini still names the profile, but its prefs.js is unreadable.
        source.set([], unreadable: [work.id])
        let second = await watcher(source).observe()

        XCTAssertEqual(second.failures.compactMap(\.scope), [FindingScope(work.id)])
        XCTAssertEqual(ledger.apply(second, rule: rule), [.becameStale(key)])
    }

    func testCancellationLeavesTheRestUnchecked() async {
        let source = FakeSource()
        source.set([work, home], dates: [work.id: now, home.id: now])
        let watcher = watcher(source)

        let task = Task { () -> WatchObservation in
            withUnsafeCurrentTask { $0?.cancel() }
            return await watcher.observe()
        }
        let observation = await task.value

        XCTAssertTrue(observation.completedScopes.isEmpty)
        XCTAssertEqual(Set(observation.failures.compactMap(\.scope)), [FindingScope(work.id), FindingScope(home.id)])
    }

    /// Watcher, file-system source and rule together, against a fixture folder.
    func testAStaleFixtureProfileBecomesASuggestion() async throws {
        let zen = try makeZenFolder()
        try zen.list(["Work", "Home"])
        try zen.snapshot("Work", at: "zen-sessions.jsonlz4", daysAgo: 10, now: now)
        try zen.snapshot("Work", at: "zen-sessions-backup/zen-sessions-a.jsonlz4", daysAgo: 8, now: now)
        try zen.snapshot("Home", at: "zen-sessions.jsonlz4", daysAgo: 1, now: now)
        let now = self.now
        let watcher = ZenSessionWatcher(source: SessionSnapshotReader(zenRoot: zen.root), now: { now })

        let observation = await watcher.observe()
        XCTAssertEqual(observation.outcome, .complete)

        let rule = SessionStalenessRule()
        let suggestions = observation.findings.compactMap { rule.suggestion(for: $0, state: .inactive) }
        XCTAssertEqual(suggestions.map(\.title), ["Zen has not saved a session in 8 days"])
        XCTAssertEqual(suggestions.first?.route.context[ZenBackupRoute.profileKey], try zen.profile("Work").id)
    }
}
