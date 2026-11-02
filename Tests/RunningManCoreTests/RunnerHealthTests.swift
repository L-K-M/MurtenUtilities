import XCTest
import MurtenCore
@testable import RunningManCore

/// The background check and its rule against fixture snapshots.
final class RunnerHealthTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let rule = RunnerOfflineRule()

    // MARK: - Check

    func testAStartAtLoginRunnerThatIsStoppedIsReportedFromItsFirstOfflineLook() {
        var memory = RunnerHealthMemory()
        let runner = snapshot("builder", status: .stopped, startsAtLogin: true)

        let first = RunnerHealthCheck.observation(of: [runner], memory: &memory, at: start)
        let later = RunnerHealthCheck.observation(of: [runner], memory: &memory, at: start + 15 * 60)

        XCTAssertEqual(first.findings.first?.date(RunnerHealthCheck.Evidence.offlineSince), start)
        XCTAssertEqual(later.findings.first?.date(RunnerHealthCheck.Evidence.offlineSince), start)
        XCTAssertEqual(later.findings.first?.text(RunnerHealthCheck.Evidence.reason), "starts-at-login")
        XCTAssertEqual(later.findings.first?.scope, FindingScope(runner.id))
        XCTAssertEqual(later.completedScopes, [FindingScope(runner.id)])
        XCTAssertEqual(later.outcome, .complete)
    }

    func testOnlineRunnersAreCheckedWithoutFindings() {
        var memory = RunnerHealthMemory()
        let idle = snapshot("idle", status: .idle, processID: 10)
        let busy = snapshot("busy", status: .busy, processID: 11)
        // A Forgejo daemon without server monitoring reads as unknown but has a process.
        let forgejo = snapshot("forgejo", status: .unknown, processID: 12, provider: .forgejo)

        let observation = RunnerHealthCheck.observation(of: [idle, busy, forgejo], memory: &memory, at: start)

        XCTAssertTrue(observation.findings.isEmpty)
        XCTAssertEqual(observation.completedScopes, Set([idle, busy, forgejo].map { FindingScope($0.id) }))
    }

    func testARunnerSeenOnlineThatStopsIsReportedEvenWithoutStartAtLogin() {
        var memory = RunnerHealthMemory()
        _ = RunnerHealthCheck.observation(of: [snapshot("manual", status: .idle, processID: 4)], memory: &memory, at: start)

        let stopped = RunnerHealthCheck.observation(of: [snapshot("manual", status: .stopped)], memory: &memory,
                                                    at: start + 60)

        XCTAssertEqual(stopped.findings.first?.text(RunnerHealthCheck.Evidence.reason), "stopped-unexpectedly")
        XCTAssertEqual(stopped.findings.first?.date(RunnerHealthCheck.Evidence.offlineSince), start + 60)
    }

    func testStoppedRunnersNothingExpectsToRunStayQuiet() {
        var memory = RunnerHealthMemory()
        let neverStarted = snapshot("spare", status: .stopped)
        let disabled = snapshot("parked", status: .disabled, startsAtLogin: true)
        let system = snapshot("system", status: .stopped, startsAtLogin: true, domain: .system)

        let observation = RunnerHealthCheck.observation(of: [neverStarted, disabled, system], memory: &memory, at: start)

        XCTAssertTrue(observation.findings.isEmpty)
        XCTAssertEqual(observation.completedScopes.count, 3, "Each was checked, so earlier suggestions resolve")
    }

    func testAStopRunningManWasAskedForIsNotReportedUntilTheRunnerRunsAgain() {
        var memory = RunnerHealthMemory()
        let online = snapshot("builder", status: .idle, processID: 4, startsAtLogin: true)
        let stopped = snapshot("builder", status: .stopped, startsAtLogin: true)
        _ = RunnerHealthCheck.observation(of: [online], memory: &memory, at: start)
        memory.acknowledgeStop(of: online.id, at: start + 60)

        XCTAssertTrue(RunnerHealthCheck.observation(of: [stopped], memory: &memory, at: start + 3600).findings.isEmpty)

        _ = RunnerHealthCheck.observation(of: [online], memory: &memory, at: start + 7200)
        let crashed = RunnerHealthCheck.observation(of: [stopped], memory: &memory, at: start + 7300)
        XCTAssertEqual(crashed.findings.count, 1, "Running again ends the acknowledgement")
    }

    func testAnOnlineLookOlderThanTheStopDoesNotEndTheAcknowledgement() {
        var memory = RunnerHealthMemory()
        let online = snapshot("builder", status: .idle, processID: 4, startsAtLogin: true)
        memory.acknowledgeStop(of: online.id, at: start + 60)
        // A refresh that started reading before the stop finishes after it.
        memory.record([online], at: start + 30)

        let observation = RunnerHealthCheck.observation(of: [snapshot("builder", status: .stopped, startsAtLogin: true)],
                                                        memory: &memory, at: start + 3600)

        XCTAssertTrue(observation.findings.isEmpty)
    }

    func testUnreadableStateIsAFailureForThatRunnerOnly() {
        var memory = RunnerHealthMemory()
        let unreadable = snapshot("unreadable", status: .unknown)
        let fine = snapshot("fine", status: .idle, processID: 3)

        let observation = RunnerHealthCheck.observation(of: [unreadable, fine], memory: &memory, at: start)

        XCTAssertEqual(observation.failures.map(\.scope), [FindingScope(unreadable.id)])
        XCTAssertEqual(observation.completedScopes, [FindingScope(fine.id)])
        XCTAssertEqual(observation.outcome, .partial)
    }

    func testAnUnreadableLookKeepsTheOfflineTime() {
        var memory = RunnerHealthMemory()
        _ = RunnerHealthCheck.observation(of: [snapshot("builder", status: .stopped, startsAtLogin: true)],
                                          memory: &memory, at: start)
        _ = RunnerHealthCheck.observation(of: [snapshot("builder", status: .unknown, startsAtLogin: true)],
                                          memory: &memory, at: start + 900)

        let observation = RunnerHealthCheck.observation(of: [snapshot("builder", status: .stopped, startsAtLogin: true)],
                                                        memory: &memory, at: start + 1800)

        XCTAssertEqual(observation.findings.first?.date(RunnerHealthCheck.Evidence.offlineSince), start)
    }

    func testARemovedRunnerIsCheckedAndAbsent() {
        var memory = RunnerHealthMemory()
        let removed = snapshot("removed", status: .stopped, startsAtLogin: true)
        _ = RunnerHealthCheck.observation(of: [removed], memory: &memory, at: start)

        let observation = RunnerHealthCheck.observation(of: [], memory: &memory, at: start + 900)

        XCTAssertEqual(observation.completedScopes, [FindingScope(removed.id)])
        XCTAssertTrue(memory.entries.isEmpty)
    }

    func testSkippedFoldersAreReportedAsNotChecked() {
        var memory = RunnerHealthMemory()
        let folder = URL(fileURLWithPath: "/Users/example/Documents/runner")

        let observation = RunnerHealthCheck.observation(of: [], skippedDirectories: [folder], memory: &memory, at: start)

        XCTAssertEqual(observation.failures.first?.kind, .permissionDenied)
        XCTAssertEqual(observation.failures.first?.scope, FindingScope(folder.path))
        XCTAssertEqual(observation.outcome, .unavailable)
    }

    func testACompleteDiscoveryListsEveryRunnerThereIs() {
        var memory = RunnerHealthMemory()
        let runner = snapshot("builder", status: .idle, processID: 3)
        XCTAssertEqual(RunnerHealthCheck.observation(of: [runner], memory: &memory, at: start).coverage, .listed)
        XCTAssertEqual(RunnerHealthCheck.observation(of: [runner], discoveryComplete: true, memory: &memory, at: start).coverage,
                       .exhaustive)
    }

    /// After a relaunch the memory is empty, so only an exhaustive look can retire the
    /// suggestion of a runner that was removed while the suite was not running.
    func testASuggestionForARemovedRunnerResolvesAfterARelaunch() {
        var ledger = SuggestionLedger()
        var memory = RunnerHealthMemory()
        let removed = snapshot("removed", status: .stopped, startsAtLogin: true)
        let kept = snapshot("kept", status: .idle, processID: 3)
        _ = RunnerHealthCheck.observation(of: [removed, kept], memory: &memory, at: start)
        ledger.apply(RunnerHealthCheck.observation(of: [removed, kept], memory: &memory, at: start + 900), rule: rule)
        let key = SuggestionKey(moduleID: "runningman", condition: RunnerHealthCheck.condition, scope: FindingScope(removed.id))
        XCTAssertEqual(ledger.records[key]?.isActive, true)

        var relaunched = RunnerHealthMemory()
        ledger.apply(RunnerHealthCheck.observation(of: [kept], memory: &relaunched, at: start + 1800), rule: rule)
        XCTAssertEqual(ledger.records[key]?.isActive, true, "A partial look proves nothing about the removed runner")
        ledger.apply(RunnerHealthCheck.observation(of: [kept], discoveryComplete: true, memory: &relaunched, at: start + 2700),
                     rule: rule)
        XCTAssertEqual(ledger.records[key]?.isActive, false)
    }

    // MARK: - Rule

    func testRuleOpensAtTenMinutesAndNamesTheRunner() throws {
        let since = start
        XCTAssertNil(rule.suggestion(for: finding(since: since, at: start + 9 * 60 + 59), state: .inactive))

        let content = try XCTUnwrap(rule.suggestion(for: finding(since: since, at: start + 12 * 60), state: .inactive))
        XCTAssertEqual(content.title, "builder has been offline for 12 min — restart?")
        XCTAssertTrue(content.detail.hasPrefix("It is set to start at login"))
        XCTAssertEqual(content.route, ModuleRoute(moduleID: "runningman", action: "runner",
                                                  context: ["id": "/Users/example/actions-runners/builder"]))
    }

    func testRuleKeepsAnOpenSuggestionUntilTheRunnerIsOnlineAgain() {
        // An open episode below the threshold (offline time remembered from a later look) stays open.
        XCTAssertNotNil(rule.suggestion(for: finding(since: start, at: start + 60), state: .active))
    }

    func testRuleIgnoresOtherConditionsAndFindingsWithoutAnOfflineTime() {
        let other = Finding(moduleID: "runningman", condition: "something-else", observedAt: start,
                            evidence: [RunnerHealthCheck.Evidence.offlineSince: .date(start - 3600)])
        let undated = Finding(moduleID: "runningman", condition: RunnerHealthCheck.condition, observedAt: start)
        XCTAssertNil(rule.suggestion(for: other, state: .inactive))
        XCTAssertNil(rule.suggestion(for: undated, state: .active))
    }

    func testRouteForAnOverlongIdentifierOpensTheRunnerList() {
        let long = "/" + String(repeating: "a", count: RouteAllowlist.maximumValueLength + 1)
        let route = RunnerOfflineRule.route(forRunner: long)
        XCTAssertEqual(route.action, "runner")
        XCTAssertTrue(route.context.isEmpty)
        XCTAssertNoThrow(try RouteAllowlist(modules: ["runningman"], actions: ["runningman": ["runner": ["id"]]]).validate(route))
    }

    func testCheckAndRuleTogetherSuggestOnlyAfterTheThreshold() {
        var memory = RunnerHealthMemory()
        let runner = snapshot("builder", status: .stopped, startsAtLogin: true)
        let first = RunnerHealthCheck.observation(of: [runner], memory: &memory, at: start)
        let second = RunnerHealthCheck.observation(of: [runner], memory: &memory, at: start + 15 * 60)

        XCTAssertNil(first.findings.first.flatMap { rule.suggestion(for: $0, state: .inactive) })
        XCTAssertEqual(second.findings.first.flatMap { rule.suggestion(for: $0, state: .inactive) }?.title,
                       "builder has been offline for 15 min — restart?")
    }

    // MARK: - Fixtures

    private func snapshot(_ name: String, status: RunnerStatus, processID: Int32? = nil, startsAtLogin: Bool = false,
                          provider: RunnerProvider = .github, domain: RunnerServiceDomain = .user) -> RunnerSnapshot {
        let runner = InstalledRunner(name: name, directory: URL(fileURLWithPath: "/Users/example/actions-runners/\(name)"),
                                     provider: provider, serviceDomain: domain)
        return RunnerSnapshot(runner: runner, status: status, processID: processID, startsAtLogin: startsAtLogin,
                              isEnabled: status != .disabled)
    }

    private func finding(since: Date, at date: Date) -> Finding {
        Finding(moduleID: "runningman", condition: RunnerHealthCheck.condition,
                scope: FindingScope("/Users/example/actions-runners/builder"), observedAt: date,
                evidence: [RunnerHealthCheck.Evidence.name: .text("builder"),
                           RunnerHealthCheck.Evidence.offlineSince: .date(since),
                           RunnerHealthCheck.Evidence.reason: .text("starts-at-login")])
    }
}
