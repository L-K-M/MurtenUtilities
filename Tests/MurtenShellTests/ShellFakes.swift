import Foundation
import SwiftUI
import MurtenCore
import MurtenModuleKit
@testable import MurtenShell

// MARK: - Clock

/// A clock that only moves when the test advances it.
final class TestClock: WatchClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private var waiters: [UUID: (deadline: Date, continuation: CheckedContinuation<Void, Error>)] = [:]

    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        current = start
    }

    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return current
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

// MARK: - Services

final class MemorySettings: SettingsPersisting {
    var stored: SuiteSettings

    init(_ settings: SuiteSettings = SuiteSettings()) {
        stored = settings
    }

    func load() -> SuiteSettings { stored }
    func save(_ settings: SuiteSettings) { stored = settings }
}

final class MemorySuggestions: SuggestionPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var saved: SuggestionLedger?

    func load() throws -> SuggestionLedger? {
        lock.lock(); defer { lock.unlock() }
        return saved
    }

    func save(_ ledger: SuggestionLedger) throws {
        lock.lock(); defer { lock.unlock() }
        saved = ledger
    }

    func quarantine() throws -> URL? { nil }
}

@MainActor
final class RecordingNotifier: SuggestionNotifying {
    var onOpen: ((URL) -> Void)?
    var authorization: NotificationAuthorization = .granted
    private(set) var delivered: [Suggestion] = []
    private(set) var withdrawn: [Set<String>] = []
    private(set) var withdrawnSuggestions: [Set<SuggestionKey>] = []

    func requestAuthorization() async -> NotificationAuthorization { authorization }

    func deliver(_ suggestion: Suggestion, moduleName: String) {
        delivered.append(suggestion)
    }

    func withdraw(modules moduleIDs: Set<String>) {
        withdrawn.append(moduleIDs)
    }

    func withdraw(suggestions keys: Set<SuggestionKey>) {
        withdrawnSuggestions.append(keys)
    }
}

struct FixedEnvironment: WatchEnvironmentSampling {
    var environment = WatchEnvironment(powerSource: .adapter, lowPowerModeEnabled: false,
                                       networkCost: .unrestricted, minuteOfDay: 12 * 60)

    func sample() async -> WatchEnvironment { environment }
}

@MainActor
final class FakeLoginItem: LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus = .disabled

    func apply(_ request: LaunchAtLoginRequest) throws {
        status = request == .register ? .enabled : .disabled
    }
}

@MainActor
final class FakeWake: SystemWakeObserving {
    private(set) var handler: (@MainActor () -> Void)?

    func observeWake(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }
}

/// Answers with a fixed release, or fails while `failure` is set, and
/// counts how often it was asked.
final class FakeUpdates: SuiteUpdateChecking, @unchecked Sendable {
    struct Offline: LocalizedError {
        var errorDescription: String? { "The Internet connection appears to be offline." }
    }

    private let lock = NSLock()
    private var answer = SuiteRelease(version: ReleaseVersion("9.9.9")!,
                                      pageURL: URL(string: "https://example.com/release")!)
    private var failing = false
    private var asked = 0

    var release: SuiteRelease {
        get { lock.withLock { answer } }
        set { lock.withLock { answer = newValue } }
    }

    var isFailing: Bool {
        get { lock.withLock { failing } }
        set { lock.withLock { failing = newValue } }
    }

    var requests: Int { lock.withLock { asked } }

    func latestRelease() async throws -> SuiteRelease {
        try lock.withLock {
            asked += 1
            if failing { throw Offline() }
            return answer
        }
    }
}

// MARK: - Module

let fakeModuleID = "dockvac"

/// The reclaimable space the fake watcher reports; a test changes it to
/// let the condition resolve.
final class ReclaimableSpace: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Int64

    init(_ bytes: Int64) {
        stored = bytes
    }

    var bytes: Int64 {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// Reports the current amount of reclaimable space, for one scope.
struct FakeWatcher: Watcher {
    let moduleID = fakeModuleID
    let cadence = WatchCadence(interval: 30 * 60)
    let clock: TestClock
    let space: ReclaimableSpace

    func observe() async -> WatchObservation {
        let finding = Finding(moduleID: moduleID, condition: "reclaimable", observedAt: clock.now(),
                              evidence: ["bytes": .bytes(space.bytes)])
        return .complete(moduleID: moduleID, at: clock.now(), findings: [finding])
    }
}

struct FakeRule: SuggestionRule {
    func suggestion(for finding: Finding, state: RuleState) -> SuggestionContent? {
        guard let bytes = finding.bytes("bytes"), bytes > 0 else { return nil }
        return SuggestionContent(title: "Docker is holding ~\(bytes) bytes", detail: "Rebuildable leftovers.",
                                 route: ModuleRoute(moduleID: fakeModuleID, action: "reclaim"))
    }
}

@MainActor
final class FakeProvider: SuiteModuleProvider {
    let moduleID = fakeModuleID
    let routeActions: [String: Set<String>] = ["reclaim": ["endpoint"]]
    var watch: WatcherRegistration?
    var applicabilityResult: Applicability = .applicable
    var busy: String?
    private(set) var panesMade: [ModuleRoute?] = []
    let context: ModuleContext

    init(context: ModuleContext, watcher: FakeWatcher?) {
        self.context = context
        watch = watcher.map { WatcherRegistration(watcher: $0, rule: FakeRule()) }
    }

    func applicability() async -> Applicability { applicabilityResult }

    func makePane(route: ModuleRoute?) -> AnyView {
        panesMade.append(route)
        return AnyView(Text("Fake pane"))
    }

    var interruptionWarning: String? { busy }
}

// MARK: - Harness

@MainActor
struct Harness {
    let model: AppModel
    let clock: TestClock
    let settings: MemorySettings
    let notifier: RecordingNotifier
    let wake: FakeWake
    let updates: FakeUpdates
    let space: ReclaimableSpace
    var provider: FakeProvider { providerBox.provider! }
    private let providerBox: ProviderBox

    final class ProviderBox {
        var provider: FakeProvider?
    }

    init(settings initial: SuiteSettings = SuiteSettings(), bytes: Int64 = 8_000_000_000,
         applicability: Applicability = .applicable, withWatcher: Bool = true) {
        let clock = TestClock()
        let settings = MemorySettings(initial)
        let notifier = RecordingNotifier()
        let wake = FakeWake()
        let updates = FakeUpdates()
        let space = ReclaimableSpace(bytes)
        let box = ProviderBox()

        let services = ShellServices(
            settings: settings, suggestionPersistence: MemorySuggestions(), notifier: notifier,
            environment: FixedEnvironment(), launchAtLogin: FakeLoginItem(), wake: wake,
            updates: updates, clock: clock, currentVersion: ReleaseVersion("0.1.0"),
            moduleDefaults: { UserDefaults(suiteName: "MurtenShellTests.\($0).\(UUID().uuidString)")! },
            stateDefaults: UserDefaults(suiteName: "MurtenShellTests.state.\(UUID().uuidString)")!)

        let factory = ModuleFactory(moduleID: fakeModuleID) { context in
            let provider = FakeProvider(context: context,
                                        watcher: withWatcher ? FakeWatcher(clock: clock, space: space) : nil)
            provider.applicabilityResult = applicability
            box.provider = provider
            return provider
        }

        model = AppModel(factories: [factory], services: services)
        self.clock = clock
        self.settings = settings
        self.notifier = notifier
        self.wake = wake
        self.updates = updates
        self.space = space
        providerBox = box
    }
}

/// Polls `condition` in real time until it holds or `timeout` passes.
@MainActor
func eventually(timeout: TimeInterval = 3, _ condition: @MainActor () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return await condition()
}
