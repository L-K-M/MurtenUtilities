import Foundation
@testable import MurtenCore

// MARK: - Dates

let t0 = Date(timeIntervalSince1970: 1_800_000_000)

func at(_ seconds: TimeInterval) -> Date {
    t0.addingTimeInterval(seconds)
}

// MARK: - Findings and rules

let dockvac = "dockvac"
let socketScope = FindingScope("unix:///var/run/docker.sock")
let sshScope = FindingScope("ssh://build-box")

let gigabyte: Int64 = 1_000_000_000

func reclaimable(_ bytes: Int64, scope: FindingScope = socketScope, at date: Date = t0) -> Finding {
    Finding(moduleID: dockvac, condition: "reclaimable", scope: scope, observedAt: date,
            evidence: ["bytes": .bytes(bytes)])
}

/// Activates at ≥ 4 GB and stays active until < 3 GB.
struct ReclaimableRule: SuggestionRule {
    func suggestion(for finding: Finding, state: RuleState) -> SuggestionContent? {
        guard let bytes = finding.bytes("bytes") else { return nil }
        let threshold = state == .active ? 3 * gigabyte : 4 * gigabyte
        guard bytes >= threshold else { return nil }
        return SuggestionContent(title: "Docker is holding ~\(bytes / gigabyte) GB",
                                 detail: "Rebuildable leftovers.",
                                 route: ModuleRoute(moduleID: dockvac, action: "reclaim"))
    }
}

func complete(_ findings: [Finding], scopes: Set<FindingScope> = [socketScope], at date: Date = t0) -> WatchObservation {
    .complete(moduleID: dockvac, at: date, scopes: scopes, findings: findings)
}

// MARK: - Persistence

final class MemoryPersistence: SuggestionPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var saved: SuggestionLedger?
    private var failure: Error?
    private(set) var quarantined = false

    init(saved: SuggestionLedger? = nil, failure: Error? = nil) {
        self.saved = saved
        self.failure = failure
    }

    var ledger: SuggestionLedger? {
        lock.lock(); defer { lock.unlock() }
        return saved
    }

    func load() throws -> SuggestionLedger? {
        lock.lock(); defer { lock.unlock() }
        if let failure { throw failure }
        return saved
    }

    func save(_ ledger: SuggestionLedger) throws {
        lock.lock(); defer { lock.unlock() }
        saved = ledger
    }

    func quarantine() throws -> URL? {
        lock.lock(); defer { lock.unlock() }
        quarantined = true
        failure = nil
        return nil
    }
}

// MARK: - Clock

/// A clock that only moves when the test advances it.
final class ManualClock: WatchClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private var waiters: [UUID: (deadline: Date, continuation: CheckedContinuation<Void, Error>)] = [:]

    init(_ start: Date = t0) {
        current = start
    }

    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    var sleeperCount: Int {
        lock.lock(); defer { lock.unlock() }
        return waiters.count
    }

    func sleep(until deadline: Date) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if Task.isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if deadline <= current {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                waiters[id] = (deadline, continuation)
                lock.unlock()
            }
        } onCancel: {
            lock.lock()
            let waiter = waiters.removeValue(forKey: id)
            lock.unlock()
            waiter?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        let now = current
        let ready = waiters.filter { $0.value.deadline <= now }
        for id in ready.keys { waiters[id] = nil }
        lock.unlock()
        for waiter in ready.values { waiter.continuation.resume() }
    }
}

/// Polls `condition` in real time until it holds or `timeout` passes.
func eventually(timeout: TimeInterval = 3, _ condition: @escaping () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return await condition()
}
