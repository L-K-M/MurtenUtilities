import XCTest
@testable import MurtenCore

final class SuggestionLedgerTests: XCTestCase {
    private let rule = ReclaimableRule()

    // MARK: - Episodes

    func testFindingOverThresholdOpensAnEpisode() {
        var ledger = SuggestionLedger()
        let events = ledger.apply(complete([reclaimable(8 * gigabyte)]), rule: rule)

        XCTAssertEqual(events, [.opened(reclaimable(0).key)])
        XCTAssertEqual(ledger.suggestions(at: t0).map(\.title), ["Docker is holding ~8 GB"])
    }

    func testFindingBelowThresholdStaysQuiet() {
        var ledger = SuggestionLedger()
        XCTAssertEqual(ledger.apply(complete([reclaimable(2 * gigabyte)]), rule: rule), [])
        XCTAssertTrue(ledger.suggestions(at: t0).isEmpty)
    }

    func testValueChangeRefreshesWithoutANewEpisode() {
        var ledger = SuggestionLedger()
        ledger.apply(complete([reclaimable(8 * gigabyte)]), rule: rule)
        let events = ledger.apply(complete([reclaimable(9 * gigabyte, at: at(60))], at: at(60)), rule: rule)

        XCTAssertEqual(events, [.refreshed(reclaimable(0).key)])
        let suggestion = ledger.suggestions(at: at(60)).first
        XCTAssertEqual(suggestion?.title, "Docker is holding ~9 GB")
        XCTAssertEqual(suggestion?.episodeStartedAt, t0)
        XCTAssertEqual(ledger.records[reclaimable(0).key]?.episode, 1)
    }

    func testHysteresisKeepsAnEpisodeOpenBetweenThresholds() {
        var ledger = SuggestionLedger()
        ledger.apply(complete([reclaimable(5 * gigabyte)]), rule: rule)
        let events = ledger.apply(complete([reclaimable(3 * gigabyte + 1, at: at(60))], at: at(60)), rule: rule)

        XCTAssertEqual(events, [.refreshed(reclaimable(0).key)])
    }

    func testCompleteCheckWithoutTheFindingResolves() {
        var ledger = SuggestionLedger()
        ledger.apply(complete([reclaimable(8 * gigabyte)]), rule: rule)
        let events = ledger.apply(complete([], at: at(60)), rule: rule)

        XCTAssertEqual(events, [.resolved(reclaimable(0).key)])
        XCTAssertTrue(ledger.suggestions(at: at(60)).isEmpty)
    }

    func testFindingBelowLowerThresholdResolves() {
        var ledger = SuggestionLedger()
        ledger.apply(complete([reclaimable(8 * gigabyte)]), rule: rule)
        let events = ledger.apply(complete([reclaimable(gigabyte, at: at(60))], at: at(60)), rule: rule)

        XCTAssertEqual(events, [.resolved(reclaimable(0).key)])
    }

    func testRecurrenceAfterResolutionOpensTheNextEpisode() {
        var ledger = SuggestionLedger()
        ledger.apply(complete([reclaimable(8 * gigabyte)]), rule: rule)
        ledger.apply(complete([], at: at(60)), rule: rule)
        let events = ledger.apply(complete([reclaimable(8 * gigabyte, at: at(120))], at: at(120)), rule: rule)

        XCTAssertEqual(events, [.opened(reclaimable(0).key)])
        XCTAssertEqual(ledger.records[reclaimable(0).key]?.episode, 2)
        XCTAssertEqual(ledger.suggestions(at: at(120)).first?.episodeStartedAt, at(120))
    }

    // MARK: - Scopes

    func testScopesNeverShareASuggestion() {
        var ledger = SuggestionLedger()
        ledger.apply(complete([reclaimable(8 * gigabyte), reclaimable(6 * gigabyte, scope: sshScope)],
                              scopes: [socketScope, sshScope]), rule: rule)

        XCTAssertEqual(ledger.suggestions(at: t0).count, 2)
    }

    func testUncheckedScopeIsLeftAlone() {
        var ledger = SuggestionLedger()
        ledger.apply(complete([reclaimable(8 * gigabyte, scope: sshScope)], scopes: [sshScope]), rule: rule)
        // A later check that only covered the socket says nothing about SSH.
        let events = ledger.apply(complete([], scopes: [socketScope], at: at(60)), rule: rule)

        XCTAssertEqual(events, [])
        XCTAssertEqual(ledger.suggestions(at: at(60)).count, 1)
    }

    func testExhaustiveCoverageResolvesScopesThatNoLongerExist() {
        var ledger = SuggestionLedger()
        ledger.apply(complete([reclaimable(8 * gigabyte, scope: sshScope)], scopes: [sshScope]), rule: rule)

        // After a relaunch the watcher lists every endpoint; the SSH one is gone.
        let gone = WatchObservation.complete(moduleID: dockvac, at: at(60), scopes: [socketScope],
                                             coverage: .exhaustive)
        XCTAssertEqual(ledger.apply(gone, rule: rule), [.resolved(reclaimable(0, scope: sshScope).key)])
    }

    func testExhaustiveCoverageTreatsAFindingAsProofItsScopeExists() {
        var ledger = SuggestionLedger()
        let lowDisk = Finding(moduleID: dockvac, condition: "low-disk", scope: sshScope, observedAt: t0,
                              evidence: ["bytes": .bytes(8 * gigabyte)])
        ledger.apply(complete([reclaimable(8 * gigabyte, scope: sshScope), lowDisk], scopes: [sshScope]), rule: rule)

        // The watcher reported a finding for the SSH scope but left it out of completedScopes.
        let sloppy = WatchObservation(moduleID: dockvac, observedAt: at(60),
                                      findings: [reclaimable(8 * gigabyte, scope: sshScope, at: at(60))],
                                      completedScopes: [socketScope], failures: [], coverage: .exhaustive)
        let events = ledger.apply(sloppy, rule: rule)
        XCTAssertFalse(events.contains(.resolved(lowDisk.key)), "the scope still exists")
    }

    func testExhaustiveCoverageKeepsFailedScopesStale() {
        var ledger = SuggestionLedger()
        ledger.apply(complete([reclaimable(8 * gigabyte, scope: sshScope)], scopes: [sshScope]), rule: rule)

        let failing = WatchObservation(
            moduleID: dockvac, observedAt: at(60), findings: [], completedScopes: [socketScope],
            failures: [ObservationFailure(kind: .unreachable, scope: sshScope, message: "host down")],
            coverage: .exhaustive)
        XCTAssertEqual(ledger.apply(failing, rule: rule), [.becameStale(reclaimable(0, scope: sshScope).key)])
    }

    func testExhaustiveCoverageIgnoresAWholeCheckFailure() {
        var ledger = SuggestionLedger()
        ledger.apply(complete([reclaimable(8 * gigabyte, scope: sshScope)], scopes: [sshScope]), rule: rule)

        let failed = WatchObservation(
            moduleID: dockvac, observedAt: at(60), findings: [], completedScopes: [],
            failures: [ObservationFailure(kind: .toolMissing, message: "no docker")], coverage: .exhaustive)
        XCTAssertEqual(ledger.apply(failed, rule: rule), [.becameStale(reclaimable(0, scope: sshScope).key)])
    }

    func testFindingsFromAnotherModuleAreIgnored() {
        var ledger = SuggestionLedger()
        let foreign = Finding(moduleID: "repomen", condition: "reclaimable", observedAt: t0,
                              evidence: ["bytes": .bytes(8 * gigabyte)])
        XCTAssertEqual(ledger.apply(complete([foreign]), rule: rule), [])
    }

    // MARK: - Failures

    func testFailedCheckMarksStaleInsteadOfResolving() {
        var ledger = SuggestionLedger()
        ledger.apply(complete([reclaimable(8 * gigabyte)]), rule: rule)
        let failure = ObservationFailure(kind: .unreachable, message: "Docker is not running")
        let events = ledger.apply(.unavailable(moduleID: dockvac, at: at(60), failure), rule: rule)

        XCTAssertEqual(events, [.becameStale(reclaimable(0).key)])
        XCTAssertEqual(ledger.suggestions(at: at(60)).first?.freshness, .stale(since: at(60)))
    }

    func testRepeatedFailureKeepsTheFirstStaleDate() {
        var ledger = SuggestionLedger()
        ledger.apply(complete([reclaimable(8 * gigabyte)]), rule: rule)
        let failure = ObservationFailure(kind: .timedOut, message: "slow")
        ledger.apply(.unavailable(moduleID: dockvac, at: at(60), failure), rule: rule)
        let events = ledger.apply(.unavailable(moduleID: dockvac, at: at(120), failure), rule: rule)

        XCTAssertEqual(events, [])
        XCTAssertEqual(ledger.suggestions(at: at(120)).first?.freshness, .stale(since: at(60)))
    }

    func testPartialFailureOnlyStalesItsScope() {
        var ledger = SuggestionLedger()
        ledger.apply(complete([reclaimable(8 * gigabyte), reclaimable(6 * gigabyte, scope: sshScope)],
                              scopes: [socketScope, sshScope]), rule: rule)
        let partial = WatchObservation(
            moduleID: dockvac, observedAt: at(60), findings: [reclaimable(8 * gigabyte, at: at(60))],
            completedScopes: [socketScope],
            failures: [ObservationFailure(kind: .unreachable, scope: sshScope, message: "host down")])
        let events = ledger.apply(partial, rule: rule)

        XCTAssertEqual(Set(events), [.refreshed(reclaimable(0).key), .becameStale(reclaimable(0, scope: sshScope).key)])
    }

    func testSuccessAfterFailureClearsStaleness() {
        var ledger = SuggestionLedger()
        ledger.apply(complete([reclaimable(8 * gigabyte)]), rule: rule)
        ledger.apply(.unavailable(moduleID: dockvac, at: at(60),
                                  ObservationFailure(kind: .unreachable, message: "down")), rule: rule)
        ledger.apply(complete([reclaimable(8 * gigabyte, at: at(120))], at: at(120)), rule: rule)

        XCTAssertEqual(ledger.suggestions(at: at(120)).first?.freshness, .current)
    }

    func testHealthKeepsLastSuccessAndFailureApart() {
        var ledger = SuggestionLedger()
        ledger.apply(complete([], at: t0), rule: rule)
        let failure = ObservationFailure(kind: .permissionDenied, message: "no access")
        ledger.apply(.unavailable(moduleID: dockvac, at: at(60), failure), rule: rule)

        let health = ledger.health[dockvac]
        XCTAssertEqual(health?.lastSuccessAt, t0)
        XCTAssertEqual(health?.lastFailureAt, at(60))
        XCTAssertEqual(health?.lastFailure, failure)
    }

    // MARK: - Snooze and dismissal

    func testSnoozeHidesUntilDeadlineAndSurvivesRefresh() {
        var ledger = SuggestionLedger()
        ledger.apply(complete([reclaimable(8 * gigabyte)]), rule: rule)
        ledger.snooze(reclaimable(0).key, until: at(3600))
        ledger.apply(complete([reclaimable(9 * gigabyte, at: at(60))], at: at(60)), rule: rule)

        XCTAssertTrue(ledger.suggestions(at: at(60)).isEmpty)
        XCTAssertEqual(ledger.suggestions(at: at(3600)).count, 1)
    }

    func testSnoozeSurvivesResolutionAndRecurrence() {
        var ledger = SuggestionLedger()
        ledger.apply(complete([reclaimable(8 * gigabyte)]), rule: rule)
        ledger.snooze(reclaimable(0).key, until: at(3600))
        ledger.apply(complete([], at: at(60)), rule: rule)
        ledger.apply(complete([reclaimable(8 * gigabyte, at: at(120))], at: at(120)), rule: rule)

        XCTAssertTrue(ledger.suggestions(at: at(120)).isEmpty)
    }

    func testDismissalHidesOnlyTheCurrentEpisode() {
        var ledger = SuggestionLedger()
        ledger.apply(complete([reclaimable(8 * gigabyte)]), rule: rule)
        XCTAssertTrue(ledger.dismiss(reclaimable(0).key))
        ledger.apply(complete([reclaimable(9 * gigabyte, at: at(60))], at: at(60)), rule: rule)
        XCTAssertTrue(ledger.suggestions(at: at(60)).isEmpty, "a value change is the same episode")

        ledger.apply(complete([], at: at(120)), rule: rule)
        ledger.apply(complete([reclaimable(8 * gigabyte, at: at(180))], at: at(180)), rule: rule)
        XCTAssertEqual(ledger.suggestions(at: at(180)).count, 1, "a recurrence is a new episode")
    }

    func testDismissingAResolvedKeyIsRejected() {
        var ledger = SuggestionLedger()
        ledger.apply(complete([reclaimable(8 * gigabyte)]), rule: rule)
        ledger.apply(complete([], at: at(60)), rule: rule)
        XCTAssertFalse(ledger.dismiss(reclaimable(0).key))
    }

    // MARK: - Notifications

    func testNotificationIsClaimedOncePerEpisode() {
        var ledger = SuggestionLedger()
        ledger.apply(complete([reclaimable(8 * gigabyte)]), rule: rule)
        let key = reclaimable(0).key

        XCTAssertTrue(ledger.claimNotification(for: key, at: t0, throttle: .standard))
        XCTAssertFalse(ledger.claimNotification(for: key, at: t0, throttle: .standard))
    }

    func testSnoozedSuggestionIsNotNotified() {
        var ledger = SuggestionLedger()
        ledger.apply(complete([reclaimable(8 * gigabyte)]), rule: rule)
        ledger.snooze(reclaimable(0).key, until: at(3600))

        XCTAssertFalse(ledger.claimNotification(for: reclaimable(0).key, at: t0, throttle: .standard))
    }

    func testThrottleLimitsDeliveriesPerWindow() {
        var ledger = SuggestionLedger()
        let scopes = (0..<4).map { FindingScope("endpoint-\($0)") }
        ledger.apply(complete(scopes.map { reclaimable(8 * gigabyte, scope: $0) }, scopes: Set(scopes)), rule: rule)
        let throttle = NotificationThrottle(maximum: 3, window: 3600)

        let claimed = scopes.filter { ledger.claimNotification(for: reclaimable(0, scope: $0).key, at: t0, throttle: throttle) }
        XCTAssertEqual(claimed.count, 3)
        XCTAssertTrue(ledger.claimNotification(for: reclaimable(0, scope: scopes[3]).key, at: at(3600), throttle: throttle))
    }

    // MARK: - Retention

    func testPruneForgetsOldResolvedEpisodesAndUnknownModules() {
        var ledger = SuggestionLedger()
        ledger.apply(complete([reclaimable(8 * gigabyte), reclaimable(8 * gigabyte, scope: sshScope)],
                              scopes: [socketScope, sshScope]), rule: rule)
        ledger.apply(complete([reclaimable(8 * gigabyte, scope: sshScope)], scopes: [socketScope, sshScope], at: at(60)),
                     rule: rule)

        let policy = RetentionPolicy(resolvedRetention: 3600, maximumRecords: 10)
        ledger.prune(at: at(60 + 3600), policy: policy, throttle: .standard, knownModules: [dockvac])
        XCTAssertEqual(ledger.records.keys.map(\.scope), [sshScope])

        ledger.prune(at: at(60 + 3600), policy: policy, throttle: .standard, knownModules: [])
        XCTAssertTrue(ledger.records.isEmpty)
    }

    func testPruneCapsRecordsEvictingResolvedFirst() {
        var ledger = SuggestionLedger()
        let scopes = (0..<3).map { FindingScope("endpoint-\($0)") }
        ledger.apply(complete(scopes.map { reclaimable(8 * gigabyte, scope: $0) }, scopes: Set(scopes)), rule: rule)
        ledger.apply(complete([reclaimable(8 * gigabyte, scope: scopes[1], at: at(60)),
                               reclaimable(8 * gigabyte, scope: scopes[2], at: at(60))],
                              scopes: Set(scopes), at: at(60)), rule: rule)

        ledger.prune(at: at(60), policy: RetentionPolicy(resolvedRetention: 86_400, maximumRecords: 2),
                     throttle: .standard, knownModules: [dockvac])
        XCTAssertEqual(Set(ledger.records.keys.map(\.scope)), [scopes[1], scopes[2]])
    }

    // MARK: - Codable

    func testLedgerRoundTripsThroughJSON() throws {
        var ledger = SuggestionLedger()
        ledger.apply(complete([reclaimable(8 * gigabyte)]), rule: rule)
        ledger.snooze(reclaimable(0).key, until: at(3600))

        let data = try JSONEncoder().encode(ledger)
        XCTAssertEqual(try JSONDecoder().decode(SuggestionLedger.self, from: data), ledger)
    }
}
