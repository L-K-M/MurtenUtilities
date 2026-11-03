import Foundation
import XCTest
import MurtenCore
@testable import CoreographyCore

final class CoreographyWatcherTests: XCTestCase {
    private let clock = FixtureClock()
    private let system = FixtureSystem()
    private lazy var watcher = CoreographyWatcher(observer: system, now: { [clock] in clock.now })

    /// Polls every 15 minutes while `Xcode` keeps a whole core busy.
    private func pollBusyXcode(polls: Int, from cpuSeconds: Double = 0, pid: Int32 = 100) async -> [WatchObservation] {
        var observations: [WatchObservation] = []
        for poll in 0..<polls {
            if poll > 0 { clock.advance(minutes: 15) }
            system.processes = .success([process("Xcode", pid: pid, cpuSeconds: cpuSeconds + Double(poll) * 900),
                                         process("idle", pid: 2, cpuSeconds: 1)])
            observations.append(await watcher.observe())
        }
        return observations
    }

    func testTheCadenceIsAtLeastFifteenMinutesAndLocal() {
        XCTAssertGreaterThanOrEqual(watcher.cadence.interval, WatchCadence.minimumInterval)
        XCTAssertFalse(watcher.cadence.resources.contains(.network))
        XCTAssertEqual(watcher.moduleID, "coreography")
    }

    func testAProcessIsReportedOnlyOnceAnHourOfItsCPUTimeIsKnown() async throws {
        let observations = await pollBusyXcode(polls: 5)

        for early in observations.prefix(4) {
            XCTAssertFalse(early.completedScopes.contains(CoreographyWatch.processesScope),
                           "before a full window, quiet processes are not known to be quiet")
            XCTAssertFalse(early.findings.contains { $0.condition.hasPrefix(CoreographyWatch.sustainedCPUPrefix) })
        }

        let hour = try XCTUnwrap(observations.last)
        XCTAssertEqual(hour.outcome, .complete)
        XCTAssertTrue(hour.completedScopes.contains(CoreographyWatch.processesScope))
        let busy = hour.findings.filter { $0.condition.hasPrefix(CoreographyWatch.sustainedCPUPrefix) }
        XCTAssertEqual(busy.map(\.condition), ["sustained-cpu:Xcode"], "the idle process is not reported")
        XCTAssertEqual(busy.first?.scope, CoreographyWatch.processesScope)
        XCTAssertEqual(busy.first?.count(CoreographyWatch.Evidence.pid), 100)
        XCTAssertNotNil(CoreographyRule().suggestion(for: try XCTUnwrap(busy.first), state: .inactive))
    }

    func testOneReadFailingMarksOnlyItsOwnScope() async {
        system.memory = .failure(unreachable)
        let observation = await watcher.observe()
        XCTAssertEqual(observation.outcome, .partial)
        XCTAssertEqual(observation.failures.map(\.scope), [CoreographyWatch.memoryScope])
        XCTAssertEqual(observation.failures.first?.message, "fixture failure")
        XCTAssertTrue(observation.completedScopes.isSuperset(of: [CoreographyWatch.thermalScope, CoreographyWatch.startupVolumeScope]))
        XCTAssertFalse(observation.completedScopes.contains(CoreographyWatch.memoryScope))
    }

    func testNothingReadableIsUnavailableNotHealthy() async {
        system.processes = .failure(unreachable)
        system.memory = .failure(unreachable)
        system.thermal = .failure(unreachable)
        system.volume = .failure(unreachable)
        let observation = await watcher.observe()
        XCTAssertEqual(observation.outcome, .unavailable)
        XCTAssertEqual(observation.failures.count, 4)
    }

    func testAVolumeWithoutASizeIsAFailure() async {
        system.volume = .success(VolumeSpace(totalBytes: 0, availableBytes: 0))
        let observation = await watcher.observe()
        XCTAssertEqual(observation.failures.first?.kind, .malformedResponse)
        XCTAssertFalse(observation.completedScopes.contains(CoreographyWatch.startupVolumeScope))
    }

    func testCriticalMemoryPressureCarriesWhenItsRunBegan() async throws {
        system.memory = .success(.critical)
        let first = await watcher.observe()
        clock.advance(minutes: 15)
        let second = await watcher.observe()

        let rule = CoreographyRule()
        let firstFinding = try XCTUnwrap(first.findings.first { $0.condition == CoreographyWatch.memoryPressure })
        let secondFinding = try XCTUnwrap(second.findings.first { $0.condition == CoreographyWatch.memoryPressure })
        XCTAssertNil(rule.suggestion(for: firstFinding, state: .inactive))
        XCTAssertNotNil(rule.suggestion(for: secondFinding, state: .inactive))
        XCTAssertEqual(secondFinding.date(CoreographyWatch.Evidence.criticalSince), firstFinding.observedAt)
    }

    func testANameIsCleanedAndBoundedForItsRoute() {
        XCTAssertEqual(CoreographyWatcher.displayName(" Bad\u{7}Name\n "), "BadName")
        XCTAssertEqual(CoreographyWatcher.displayName(String(repeating: "x", count: 200)).count, CoreographyWatch.maximumNameLength)
    }

    // MARK: - Through the suite's ledger

    private func active(_ ledger: SuggestionLedger) -> [SuggestionKey] {
        ledger.records.values.filter(\.isActive).map(\.key)
    }

    func testAnExitedProcessResolvesItsSuggestion() async throws {
        var ledger = SuggestionLedger()
        let rule = CoreographyRule()
        for observation in await pollBusyXcode(polls: 5) { ledger.apply(observation, rule: rule) }
        XCTAssertEqual(active(ledger).map(\.condition), ["sustained-cpu:Xcode"])

        clock.advance(minutes: 15)
        system.processes = .success([process("idle", pid: 2, cpuSeconds: 1)])
        let events = ledger.apply(await watcher.observe(), rule: rule)
        XCTAssertTrue(events.contains(.resolved(SuggestionKey(moduleID: "coreography", condition: "sustained-cpu:Xcode",
                                                              scope: CoreographyWatch.processesScope))))
        XCTAssertTrue(active(ledger).isEmpty)
    }

    func testAfterARestartASuggestionIsNotResolvedBeforeAFullWindow() async throws {
        var ledger = SuggestionLedger()
        let rule = CoreographyRule()
        for observation in await pollBusyXcode(polls: 5) { ledger.apply(observation, rule: rule) }

        // A new launch: a fresh watcher, the ledger restored from disk.
        let restarted = CoreographyWatcher(observer: system, now: { [clock] in clock.now })
        clock.advance(minutes: 15)
        system.processes = .success([process("Xcode", pid: 100, cpuSeconds: 5000)])
        ledger.apply(await restarted.observe(), rule: rule)
        XCTAssertEqual(active(ledger).map(\.condition), ["sustained-cpu:Xcode"],
                       "not measured yet is not the same as quiet")
    }

    func testFailedProcessReadsMakeTheSuggestionStaleNotResolved() async throws {
        var ledger = SuggestionLedger()
        let rule = CoreographyRule()
        for observation in await pollBusyXcode(polls: 5) { ledger.apply(observation, rule: rule) }

        clock.advance(minutes: 15)
        system.processes = .failure(unreachable)
        let events = ledger.apply(await watcher.observe(), rule: rule)
        XCTAssertTrue(events.contains { if case .becameStale = $0 { true } else { false } })
        XCTAssertEqual(active(ledger).count, 1)
    }

    func testCancellationFailsWhatWasNotChecked() async {
        let watcher = self.watcher
        let task = Task { () -> WatchObservation in
            withUnsafeCurrentTask { $0?.cancel() }
            return await watcher.observe()
        }
        let observation = await task.value
        XCTAssertTrue(observation.failures.contains { $0.scope == nil && $0.message == "The check was cancelled." })
        XCTAssertFalse(observation.completedScopes.contains(CoreographyWatch.memoryScope))
    }
}
