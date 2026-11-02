import XCTest
@testable import MurtenCore

/// Records sink deliveries.
private actor Inbox {
    private(set) var observations: [WatchObservation] = []

    func add(_ observation: WatchObservation) {
        observations.append(observation)
    }
}

/// A watcher whose polls the test releases one at a time.
private final class GatedWatcher: Watcher, @unchecked Sendable {
    let moduleID: String
    let cadence: WatchCadence
    private let clock: ManualClock
    private let lock = NSLock()
    private var started = 0
    private var cancelled = 0
    private var pending: [CheckedContinuation<Void, Never>] = []

    init(clock: ManualClock, timeout: TimeInterval = 60, moduleID: String = dockvac) {
        self.moduleID = moduleID
        self.clock = clock
        cadence = WatchCadence(interval: 30 * 60, timeout: timeout)
    }

    var startedCount: Int { lock.lock(); defer { lock.unlock() }; return started }
    var cancelledCount: Int { lock.lock(); defer { lock.unlock() }; return cancelled }
    var waitingCount: Int { lock.lock(); defer { lock.unlock() }; return pending.count }

    func releaseAll() {
        lock.lock()
        let waiting = pending
        pending = []
        lock.unlock()
        waiting.forEach { $0.resume() }
    }

    private func recordStart() {
        lock.lock(); started += 1; lock.unlock()
    }

    func observe() async -> WatchObservation {
        recordStart()

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock(); pending.append(continuation); lock.unlock()
            }
        } onCancel: {
            self.lock.lock(); self.cancelled += 1; self.lock.unlock()
            self.releaseAll()
        }

        return .complete(moduleID: moduleID, at: clock.now(),
                         findings: [Finding(moduleID: moduleID, condition: "reclaimable", observedAt: clock.now())])
    }
}

private struct AlwaysRule: SuggestionRule {
    func suggestion(for finding: Finding, state: RuleState) -> SuggestionContent? {
        SuggestionContent(title: "t", detail: "d", route: ModuleRoute(moduleID: finding.moduleID))
    }
}

final class WatchCoordinatorTests: XCTestCase {
    private func makeCoordinator(watcher: GatedWatcher, clock: ManualClock, inbox: Inbox,
                                 gate: WatchGate = .open) -> WatchCoordinator {
        WatchCoordinator(
            registrations: [WatcherRegistration(watcher: watcher, rule: AlwaysRule())],
            clock: clock,
            gate: { _ in gate },
            sink: { observation, _ in await inbox.add(observation) })
    }

    func testPollsAfterInitialDelayAndDeliversTheResult() async {
        let clock = ManualClock()
        let watcher = GatedWatcher(clock: clock)
        let inbox = Inbox()
        let coordinator = makeCoordinator(watcher: watcher, clock: clock, inbox: inbox)

        await coordinator.setEnabled([dockvac])
        let sleeping = await eventually { clock.sleeperCount == 1 }
        XCTAssertTrue(sleeping)
        XCTAssertEqual(watcher.startedCount, 0)

        clock.advance(by: WatchSchedule.initialDelay)
        let polling = await eventually { watcher.waitingCount == 1 }
        XCTAssertTrue(polling)
        watcher.releaseAll()

        let delivered = await eventually { await inbox.observations.count == 1 }
        XCTAssertTrue(delivered)
        await coordinator.setEnabled([])
    }

    func testAtMostOnePollInFlightPerWatcher() async {
        let clock = ManualClock()
        let watcher = GatedWatcher(clock: clock, timeout: 24 * 3600)
        let inbox = Inbox()
        let coordinator = makeCoordinator(watcher: watcher, clock: clock, inbox: inbox)

        await coordinator.setEnabled([dockvac])
        _ = await eventually { clock.sleeperCount >= 1 }
        clock.advance(by: WatchSchedule.initialDelay)
        _ = await eventually { watcher.waitingCount == 1 }

        // Several intervals pass while the first poll is still running.
        for _ in 0..<3 {
            clock.advance(by: 30 * 60)
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(watcher.startedCount, 1)
        await coordinator.setEnabled([])
    }

    func testDisablingCancelsThePollAndDropsItsLateResult() async {
        let clock = ManualClock()
        let watcher = GatedWatcher(clock: clock, timeout: 24 * 3600)
        let inbox = Inbox()
        let coordinator = makeCoordinator(watcher: watcher, clock: clock, inbox: inbox)

        await coordinator.setEnabled([dockvac])
        _ = await eventually { clock.sleeperCount >= 1 }
        clock.advance(by: WatchSchedule.initialDelay)
        _ = await eventually { watcher.waitingCount == 1 }

        await coordinator.setEnabled([])
        let cancelled = await eventually { watcher.cancelledCount == 1 }
        XCTAssertTrue(cancelled, "disabling must stop the watcher's work, not just stop awaiting it")

        try? await Task.sleep(nanoseconds: 50_000_000)
        let count = await inbox.observations.count
        XCTAssertEqual(count, 0)
        let inFlight = await coordinator.pollsInFlight
        XCTAssertTrue(inFlight.isEmpty)
    }

    func testTimeoutReportsTheCheckUnavailable() async {
        let clock = ManualClock()
        let watcher = GatedWatcher(clock: clock, timeout: 60)
        let inbox = Inbox()
        let coordinator = makeCoordinator(watcher: watcher, clock: clock, inbox: inbox)

        await coordinator.setEnabled([dockvac])
        _ = await eventually { clock.sleeperCount >= 1 }
        clock.advance(by: WatchSchedule.initialDelay)
        _ = await eventually { watcher.waitingCount == 1 }

        clock.advance(by: 60)
        let delivered = await eventually { await inbox.observations.count == 1 }
        XCTAssertTrue(delivered)
        let observation = await inbox.observations.first
        XCTAssertEqual(observation?.failures.first?.kind, .timedOut)
        XCTAssertEqual(watcher.cancelledCount, 1)
        await coordinator.setEnabled([])
    }

    func testPausedGatePostponesThePoll() async {
        let clock = ManualClock()
        let watcher = GatedWatcher(clock: clock)
        let inbox = Inbox()
        let coordinator = makeCoordinator(watcher: watcher, clock: clock, inbox: inbox, gate: .paused(.battery))

        await coordinator.setEnabled([dockvac])
        _ = await eventually { clock.sleeperCount >= 1 }
        clock.advance(by: WatchSchedule.initialDelay)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(watcher.startedCount, 0)
        await coordinator.setEnabled([])
    }

    func testWaitsQuietlyWhileEveryPollSlotIsBusy() async {
        let clock = ManualClock()
        let watchers = ["a", "b", "c"].map { GatedWatcher(clock: clock, timeout: 24 * 3600, moduleID: $0) }
        let inbox = Inbox()
        let coordinator = WatchCoordinator(
            registrations: watchers.map { WatcherRegistration(watcher: $0, rule: AlwaysRule()) },
            clock: clock, gate: { _ in .open }, sink: { observation, _ in await inbox.add(observation) })

        await coordinator.setEnabled(["a", "b", "c"])
        _ = await eventually { clock.sleeperCount >= 1 }
        clock.advance(by: WatchSchedule.initialDelay)
        let twoRunning = await eventually { watchers.map(\.waitingCount).reduce(0, +) == WatchCoordinator.maximumConcurrentPolls }
        XCTAssertTrue(twoRunning)

        // The third poll is due but has no slot: the loop must wait, not spin.
        let callsBefore = clock.sleepCalls
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertLessThan(clock.sleepCalls - callsBefore, 5)

        // A finished poll frees a slot for the waiting one.
        watchers.first { $0.waitingCount == 1 }?.releaseAll()
        let thirdStarted = await eventually { watchers.allSatisfy { $0.startedCount == 1 } }
        XCTAssertTrue(thirdStarted)
        await coordinator.setEnabled([])
    }

    func testUnknownModulesAreIgnored() async {
        let clock = ManualClock()
        let coordinator = makeCoordinator(watcher: GatedWatcher(clock: clock), clock: clock, inbox: Inbox())
        await coordinator.setEnabled(["nonexistent"])
        let enabled = await coordinator.enabledModules
        XCTAssertTrue(enabled.isEmpty)
    }
}
