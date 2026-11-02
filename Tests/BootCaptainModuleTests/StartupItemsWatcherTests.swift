import XCTest
import MurtenCore
import BootCaptainCore
@testable import BootCaptainModule

final class StartupItemsWatcherTests: XCTestCase {
    private let old = agent("com.vendor.old")
    private let dockerHelper = agent("com.docker.helper",
                                     app: AppIdentity(name: "Docker", bundleIdentifier: "com.docker.docker"),
                                     mechanism: .smAppServiceDaemon)
    private let dockerSocket = agent("com.docker.socket", associated: ["com.docker.docker"])

    func testCadenceIsRareAndLocal() {
        let cadence = watcher([], reviewed: .notYetReviewed).cadence
        XCTAssertGreaterThanOrEqual(cadence.interval, WatchCadence.minimumInterval)
        XCTAssertFalse(cadence.resources.contains(.network))
    }

    func testWithoutAReviewedInventoryTheCheckIsUnavailableNotEmpty() async {
        let observation = await watcher([dockerHelper], reviewed: .notYetReviewed).observe()
        XCTAssertEqual(observation.outcome, .unavailable)
        XCTAssertEqual(observation.failures.first?.kind, .toolMissing)
        XCTAssertTrue(observation.findings.isEmpty)
    }

    func testUnreadableReviewedInventoryIsAFailure() async {
        let observation = await watcher([dockerHelper], reviewed: .unreadable).observe()
        XCTAssertEqual(observation.outcome, .unavailable)
        XCTAssertEqual(observation.failures.first?.kind, .malformedResponse)
    }

    func testCompleteCheckReportsOneFindingPerProduct() async throws {
        let observation = await watcher([old, dockerHelper, dockerSocket], reviewed: .reviewed(reviewed([old])),
                                        installedApps: ["com.docker.docker": "Docker"]).observe()

        XCTAssertEqual(observation.outcome, .complete)
        XCTAssertEqual(observation.completedScopes, [.local])
        XCTAssertEqual(observation.findings.count, 1)
        let finding = try XCTUnwrap(observation.findings.first)
        XCTAssertEqual(finding.count("count"), 2)
        XCTAssertEqual(finding.text("product"), "Docker")
        XCTAssertEqual(finding.observedAt, fixtureDate)
    }

    func testCompleteCheckWithNothingNewHasNoFindings() async {
        let observation = await watcher([old], reviewed: .reviewed(reviewed([old]))).observe()
        XCTAssertEqual(observation.outcome, .complete)
        XCTAssertTrue(observation.findings.isEmpty)
    }

    func testUnreadableFolderMakesTheCheckPartialAndKeepsWhatItSaw() async {
        let failure = InventoryReadFailure(kind: .unreadable, path: "/Library/LaunchDaemons", reason: "Permission denied")
        let observation = await watcher([dockerHelper], reviewed: .reviewed(reviewed([])),
                                        failures: [failure]).observe()

        XCTAssertEqual(observation.outcome, .partial)
        XCTAssertTrue(observation.completedScopes.isEmpty)
        XCTAssertEqual(observation.findings.count, 1)
        XCTAssertEqual(observation.failures.first?.kind, .permissionDenied)
        XCTAssertEqual(observation.failures.first?.scope, .local)
        XCTAssertTrue(observation.failures.first?.message.contains("/Library/LaunchDaemons") ?? false)
    }

    func testCancelledReadIsReportedAsTimedOut() async {
        let failure = InventoryReadFailure(kind: .cancelled, path: "/Applications", reason: "The check was cancelled.")
        let observation = await watcher([], reviewed: .reviewed(reviewed([])), failures: [failure]).observe()
        XCTAssertEqual(observation.outcome, .unavailable)
        XCTAssertEqual(observation.failures.first?.kind, .timedOut)
    }

    // MARK: - Through the suite's ledger

    func testReviewingInThePaneResolvesTheSuggestion() async {
        var ledger = SuggestionLedger()
        let rule = NewStartupItemsRule()

        let first = await watcher([old, dockerHelper], reviewed: .reviewed(reviewed([old]))).observe()
        let opened = ledger.apply(first, rule: rule)
        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(ledger.suggestions(at: fixtureDate).first?.title, "Docker installed 1 new startup item")

        // The user marked the list as reviewed: both items are now known.
        let second = await watcher([old, dockerHelper], reviewed: .reviewed(reviewed([old, dockerHelper]))).observe()
        let events = ledger.apply(second, rule: rule)
        XCTAssertEqual(events.count, 1)
        guard case .resolved = events.first else { return XCTFail("expected resolution, got \(events)") }
        XCTAssertTrue(ledger.suggestions(at: fixtureDate).isEmpty)
    }

    func testUninstalledProductResolvesToo() async {
        var ledger = SuggestionLedger()
        let rule = NewStartupItemsRule()

        ledger.apply(await watcher([old, dockerHelper], reviewed: .reviewed(reviewed([old]))).observe(), rule: rule)
        // Docker is gone; the reviewed list was never updated.
        ledger.apply(await watcher([old], reviewed: .reviewed(reviewed([old]))).observe(), rule: rule)

        XCTAssertTrue(ledger.suggestions(at: fixtureDate).isEmpty)
    }

    func testAPartialCheckLeavesTheSuggestionStaleInsteadOfResolved() async {
        var ledger = SuggestionLedger()
        let rule = NewStartupItemsRule()
        ledger.apply(await watcher([old, dockerHelper], reviewed: .reviewed(reviewed([old]))).observe(), rule: rule)

        let failure = InventoryReadFailure(kind: .unreadable, path: "/Applications", reason: "Permission denied")
        ledger.apply(await watcher([old], reviewed: .reviewed(reviewed([old])), failures: [failure]).observe(),
                     rule: rule)

        let suggestions = ledger.suggestions(at: fixtureDate)
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.freshness, .stale(since: fixtureDate))
    }

    func testAThirdItemRefreshesTheEpisodeInsteadOfOpeningANewOne() async {
        var ledger = SuggestionLedger()
        let rule = NewStartupItemsRule()
        ledger.apply(await watcher([dockerHelper], reviewed: .reviewed(reviewed([]))).observe(), rule: rule)
        let events = ledger.apply(await watcher([dockerHelper, dockerSocket], reviewed: .reviewed(reviewed([])),
                                                installedApps: ["com.docker.docker": "Docker"]).observe(),
                                  rule: rule)

        guard case .refreshed = events.first else { return XCTFail("expected refresh, got \(events)") }
        XCTAssertEqual(ledger.suggestions(at: fixtureDate).first?.title, "Docker installed 2 new startup items")
    }
}

final class ReviewedInventoryStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "BootCaptainModuleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testRoundTripsAndStartsUnreviewed() {
        let store = ReviewedInventoryStore(defaults: makeDefaults())
        XCTAssertEqual(store.reviewedInventory(), .notYetReviewed)

        let inventory = ReviewedInventory(reviewedAt: fixtureDate, itemIDs: ["launchAgent:a", "launchDaemon:b"])
        XCTAssertTrue(store.save(inventory))
        XCTAssertEqual(store.reviewedInventory(), .reviewed(inventory))
    }

    func testGarbageIsUnreadableNotEmpty() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: ReviewedInventoryStore.defaultsKey)
        XCTAssertEqual(ReviewedInventoryStore(defaults: defaults).reviewedInventory(), .unreadable)
    }
}
