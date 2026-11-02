import Foundation

/// Time for the coordinator, injectable so tests never wait on a real clock.
public protocol WatchClock: Sendable {
    func now() -> Date
    /// Suspends until `deadline`; throws `CancellationError` when cancelled.
    func sleep(until deadline: Date) async throws
}

public struct SystemWatchClock: WatchClock {
    public init() {}

    public func now() -> Date { Date() }

    public func sleep(until deadline: Date) async throws {
        // Capped at a day so the nanosecond count can never overflow.
        let interval = min(deadline.timeIntervalSinceNow, 24 * 3600)
        guard interval > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }
}

/// The one owner of background checks. It schedules every enabled watcher,
/// keeps at most one poll in flight per watcher and `maximumConcurrentPolls`
/// overall, enforces each cadence's timeout, honors the pause gate, and
/// drops results that arrive after their watcher was disabled.
///
///     loop: start due polls (gate open, under the concurrency bound)
///           sleep until the next deadline or a signal (enable, wake, finish)
///     poll: observe ─race─ timeout → generation still current? → sink
///
/// A watcher that ignores cancellation past its timeout is abandoned: its
/// slot frees and the timeout is reported, but it does not poll again
/// until the abandoned work has ended, so polls never overlap.
public actor WatchCoordinator {
    public typealias Gate = @Sendable (WatchResources) async -> WatchGate
    public typealias Sink = @Sendable (WatchObservation, WatcherRegistration) async -> Void

    public static let maximumConcurrentPolls = 2

    private let registrations: [String: WatcherRegistration]
    private let clock: any WatchClock
    private let gate: Gate
    private let sink: Sink

    private var schedule = WatchSchedule()
    private var enabled: Set<String> = []
    private var inFlight: [String: Task<Void, Never>] = [:]
    /// Timed-out polls whose watcher has not stopped yet.
    private var abandoned: Set<String> = []
    /// Bumped when a watcher is disabled, so its late result is dropped.
    private var generations: [String: Int] = [:]
    private var loop: Task<Void, Never>?
    private var sleeper: Task<Void, Never>?

    public init(registrations: [WatcherRegistration], clock: any WatchClock = SystemWatchClock(),
                gate: @escaping Gate, sink: @escaping Sink) {
        self.registrations = Dictionary(registrations.map { ($0.moduleID, $0) },
                                        uniquingKeysWith: { first, _ in first })
        self.clock = clock
        self.gate = gate
        self.sink = sink
    }

    // MARK: - Control

    /// Runs exactly these watchers; others are cancelled and their pending
    /// results discarded. An empty set stops all background work.
    public func setEnabled(_ moduleIDs: Set<String>) {
        let wanted = moduleIDs.intersection(registrations.keys)
        let now = clock.now()

        for moduleID in enabled.subtracting(wanted) {
            generations[moduleID, default: 0] += 1
            inFlight.removeValue(forKey: moduleID)?.cancel()
            schedule.unregister(moduleID)
        }
        for moduleID in wanted.subtracting(enabled) {
            guard let registration = registrations[moduleID] else { continue }
            schedule.register(moduleID, interval: registration.watcher.cadence.interval, at: now)
        }
        enabled = wanted

        if enabled.isEmpty {
            loop?.cancel()
            loop = nil
            sleeper?.cancel()
            return
        }
        if loop == nil {
            loop = Task { [weak self] in await self?.run() }
        }
        signal()
    }

    /// The system woke from sleep: run overdue checks once, after settling.
    public func systemDidWake() {
        schedule.wake(at: clock.now())
        signal()
    }

    /// Polls a module soon, e.g. after the user acted in its pane.
    public func expedite(_ moduleID: String) {
        guard enabled.contains(moduleID) else { return }
        schedule.expedite(moduleID, at: clock.now())
        signal()
    }

    public var enabledModules: Set<String> { enabled }
    public var pollsInFlight: Set<String> { Set(inFlight.keys) }
    public var pollsAbandoned: Set<String> { abandoned }

    // MARK: - Loop

    private func run() async {
        while !Task.isCancelled {
            await startDuePolls()
            guard !Task.isCancelled else { return }
            await sleepUntilNextDeadline()
        }
    }

    private func startDuePolls() async {
        for moduleID in schedule.dueModules(at: clock.now()) {
            guard inFlight.count < Self.maximumConcurrentPolls else { return }
            guard let registration = registrations[moduleID] else { continue }

            // Still running past its timeout; never overlap two polls.
            guard !abandoned.contains(moduleID) else {
                schedule.postpone(moduleID, at: clock.now())
                continue
            }

            let verdict = await gate(registration.watcher.cadence.resources)
            // The gate suspended; the watcher may have been disabled meanwhile.
            guard enabled.contains(moduleID), inFlight[moduleID] == nil else { continue }

            guard verdict == .open else {
                schedule.postpone(moduleID, at: clock.now())
                continue
            }
            launch(registration)
        }
    }

    private func sleepUntilNextDeadline() async {
        let idleDeadline = clock.now().addingTimeInterval(WatchSchedule.pauseRecheckInterval)
        // With every slot busy, a due poll cannot start before one finishes,
        // and `finish` signals; sleeping until its past deadline would spin.
        let slotsFull = inFlight.count >= Self.maximumConcurrentPolls
        let deadline = slotsFull ? idleDeadline : (schedule.nextDeadline() ?? idleDeadline)
        let clock = self.clock
        let task = Task<Void, Never> { _ = try? await clock.sleep(until: deadline) }
        sleeper = task
        await task.value
        // A loop cancelled by a disable can resume after a re-enable started
        // a new loop; it must not clear the new loop's sleeper.
        if sleeper == task { sleeper = nil }
    }

    /// Ends the current sleep so the loop re-evaluates the schedule.
    private func signal() {
        sleeper?.cancel()
    }

    // MARK: - Polls

    private func launch(_ registration: WatcherRegistration) {
        let moduleID = registration.moduleID
        let generation = generations[moduleID, default: 0]
        schedule.markStarted(moduleID)

        let clock = self.clock
        inFlight[moduleID] = Task { [weak self] in
            let watcher = registration.watcher
            let work = Task { await watcher.observe() }

            let observation: WatchObservation
            switch await Self.race(work, timeout: watcher.cadence.timeout, clock: clock) {
            case .finished(let result):
                observation = result
            case .timedOut:
                work.cancel()
                await self?.abandon(moduleID, work: work)
                let failure = ObservationFailure(
                    kind: .timedOut, message: "The check took longer than \(Int(watcher.cadence.timeout)) seconds.")
                observation = .unavailable(moduleID: moduleID, at: clock.now(), failure)
            }
            await self?.finish(registration, generation: generation, observation: observation)
        }
    }

    /// Tracks a timed-out poll until its watcher actually stops.
    private func abandon(_ moduleID: String, work: Task<WatchObservation, Never>) {
        abandoned.insert(moduleID)
        Task { [weak self] in
            _ = await work.value
            await self?.releaseAbandoned(moduleID)
        }
    }

    private func releaseAbandoned(_ moduleID: String) {
        abandoned.remove(moduleID)
        signal()
    }

    private func finish(_ registration: WatcherRegistration, generation: Int, observation: WatchObservation) async {
        let moduleID = registration.moduleID
        // A disabled watcher's result is discarded, even if it completed.
        guard generations[moduleID, default: 0] == generation, enabled.contains(moduleID) else { return }

        inFlight[moduleID] = nil
        let completion: WatchSchedule.Completion = observation.outcome == .unavailable ? .failed : .succeeded
        schedule.markFinished(moduleID, completion, at: clock.now())
        signal()

        await sink(observation, registration)
    }

    private enum RaceOutcome: Sendable {
        case finished(WatchObservation)
        case timedOut
    }

    /// Waits for the watcher's work or its timeout, whichever comes first.
    /// Unlike a task group, this returns at the timeout even when the work
    /// ignores cancellation. Cancelling the caller cancels the work.
    private static func race(_ work: Task<WatchObservation, Never>, timeout: TimeInterval,
                             clock: any WatchClock) async -> RaceOutcome {
        let deadline = clock.now().addingTimeInterval(timeout)
        let race = RaceState()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<RaceOutcome, Never>) in
                race.install(continuation)
                let timer = Task {
                    try? await clock.sleep(until: deadline)
                    race.resolve(.timedOut)
                }
                Task {
                    let result = await work.value
                    timer.cancel()
                    race.resolve(.finished(result))
                }
            }
        } onCancel: {
            work.cancel()
        }
    }

    /// Resumes the race's continuation exactly once.
    private final class RaceState: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<RaceOutcome, Never>?

        func install(_ continuation: CheckedContinuation<RaceOutcome, Never>) {
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }

        func resolve(_ outcome: RaceOutcome) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: outcome)
        }
    }
}
