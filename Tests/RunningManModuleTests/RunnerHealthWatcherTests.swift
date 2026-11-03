import XCTest
import MurtenCore
import RunningManCore
import RunningManServices
@testable import RunningManModule

/// The watcher against fixture readings; it never looks at this Mac's runners.
final class RunnerHealthWatcherTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testCadenceIsLocalAndNoMoreOftenThanEveryFifteenMinutes() {
        let watcher = makeWatcher(FixtureProbe(), memory: RunnerHealthMemoryStore())
        XCTAssertEqual(watcher.moduleID, "runningman")
        XCTAssertGreaterThanOrEqual(watcher.cadence.interval, 15 * 60)
        XCTAssertFalse(watcher.cadence.resources.contains(.network), "It reads launchd and the process list only")
    }

    func testAnOfflineRunnerBecomesASuggestionAfterTenMinutesAndResolvesOnceOnline() async {
        let probe = FixtureProbe()
        let clock = FixtureClock(start)
        let watcher = makeWatcher(probe, memory: RunnerHealthMemoryStore(), clock: clock)
        var ledger = SuggestionLedger()
        let runner = snapshot("builder", status: .stopped, startsAtLogin: true)

        probe.set([runner])
        let first = await watcher.observe()
        ledger.apply(first, rule: RunnerOfflineRule())
        XCTAssertTrue(ledger.records.isEmpty, "Offline for less than ten minutes")

        clock.advance(by: 15 * 60)
        let second = await watcher.observe()
        ledger.apply(second, rule: RunnerOfflineRule())
        let key = SuggestionKey(moduleID: "runningman", condition: "runner-offline", scope: FindingScope(runner.id))
        XCTAssertEqual(ledger.records[key]?.content.title, "builder has been offline for 15 min — restart?")
        XCTAssertEqual(ledger.records[key]?.content.route,
                       ModuleRoute(moduleID: "runningman", action: "runner", context: ["id": runner.id]))

        clock.advance(by: 15 * 60)
        probe.set([snapshot("builder", status: .idle, processID: 7, startsAtLogin: true)])
        let online = await watcher.observe()
        ledger.apply(online, rule: RunnerOfflineRule())
        XCTAssertEqual(ledger.records[key]?.isActive, false)
    }

    func testAStopAskedForInThePaneIsNotReported() async {
        let probe = FixtureProbe()
        let memory = RunnerHealthMemoryStore()
        let clock = FixtureClock(start)
        let watcher = makeWatcher(probe, memory: memory, clock: clock)
        let online = snapshot("builder", status: .idle, processID: 7, startsAtLogin: true)

        await memory.record([online], at: start)
        await memory.acknowledgeStop(of: online.id, at: start + 1)
        clock.advance(by: 3600)
        probe.set([snapshot("builder", status: .stopped, startsAtLogin: true)])

        let observation = await watcher.observe()
        XCTAssertTrue(observation.findings.isEmpty)
        XCTAssertEqual(observation.completedScopes, [FindingScope(online.id)])
    }

    func testACompleteReadingRetiresSuggestionsOfRunnersThatAreGone() async {
        let probe = FixtureProbe()
        let clock = FixtureClock(start)
        var ledger = SuggestionLedger()
        let removed = snapshot("removed", status: .stopped, startsAtLogin: true)
        let first = makeWatcher(probe, memory: RunnerHealthMemoryStore(), clock: clock)
        probe.set([removed])
        _ = await first.observe()
        clock.advance(by: 15 * 60)
        let opened = await first.observe()
        ledger.apply(opened, rule: RunnerOfflineRule())

        // A relaunch starts with empty memory; the runner was deleted meanwhile.
        let relaunched = makeWatcher(probe, memory: RunnerHealthMemoryStore(), clock: clock)
        probe.set([], complete: true)
        clock.advance(by: 15 * 60)
        let after = await relaunched.observe()
        ledger.apply(after, rule: RunnerOfflineRule())

        let key = SuggestionKey(moduleID: "runningman", condition: "runner-offline", scope: FindingScope(removed.id))
        XCTAssertEqual(ledger.records[key]?.isActive, false)
    }

    func testImportedFoldersAreReadOnEveryCheck() async {
        let probe = FixtureProbe()
        let folder = URL(fileURLWithPath: "/Users/example/Elsewhere/runner")
        let watcher = RunnerHealthWatcher(probe: probe, memory: RunnerHealthMemoryStore(),
                                          additionalDirectories: { [folder] })

        _ = await watcher.observe()

        XCTAssertEqual(probe.requestedDirectories, [[folder]])
    }

    func testSkippedProtectedFoldersAreReportedAsNotChecked() async {
        let probe = FixtureProbe()
        let folder = URL(fileURLWithPath: "/Users/example/Documents/runner")
        probe.set([], skipped: [folder])

        let observation = await makeWatcher(probe, memory: RunnerHealthMemoryStore()).observe()

        XCTAssertEqual(observation.failures.map(\.kind), [.permissionDenied])
        XCTAssertEqual(observation.failures.first?.scope, FindingScope(folder.path))
    }

    func testACancelledCheckReportsItselfInsteadOfUnreadableRunners() async {
        let probe = FixtureProbe()
        probe.set([snapshot("builder", status: .unknown)])
        probe.delay = .seconds(30)
        let watcher = makeWatcher(probe, memory: RunnerHealthMemoryStore())

        let check = Task { await watcher.observe() }
        try? await Task.sleep(for: .milliseconds(50))
        check.cancel()
        let observation = await check.value

        XCTAssertEqual(observation.outcome, .unavailable)
        XCTAssertTrue(observation.findings.isEmpty)
        XCTAssertNil(observation.failures.first?.scope)
    }

    // MARK: - Fixtures

    private func makeWatcher(_ probe: FixtureProbe, memory: RunnerHealthMemoryStore,
                             clock: FixtureClock? = nil) -> RunnerHealthWatcher {
        let clock = clock ?? FixtureClock(start)
        return RunnerHealthWatcher(probe: probe, memory: memory, additionalDirectories: { [] }, now: { clock.now })
    }

    private func snapshot(_ name: String, status: RunnerStatus, processID: Int32? = nil,
                          startsAtLogin: Bool = false) -> RunnerSnapshot {
        let runner = InstalledRunner(name: name, directory: URL(fileURLWithPath: "/Users/example/actions-runners/\(name)"))
        return RunnerSnapshot(runner: runner, status: status, processID: processID, startsAtLogin: startsAtLogin)
    }
}

/// Serves scripted readings and records what the watcher asked for.
final class FixtureProbe: RunnerStateProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var reading = RunnerStateReading(snapshots: [])
    private var requests: [[URL]] = []
    var delay: Duration?

    func set(_ snapshots: [RunnerSnapshot], skipped: [URL] = [], complete: Bool = false) {
        lock.withLock {
            reading = RunnerStateReading(snapshots: snapshots, skippedDirectories: skipped, discoveryComplete: complete)
        }
    }

    var requestedDirectories: [[URL]] { lock.withLock { requests } }

    func read(additionalDirectories: [URL]) async -> RunnerStateReading {
        lock.withLock { requests.append(additionalDirectories) }
        if let delay { try? await Task.sleep(for: delay) }
        return lock.withLock { reading }
    }
}

final class FixtureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) {
        current = start
    }

    var now: Date { lock.withLock { current } }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}
