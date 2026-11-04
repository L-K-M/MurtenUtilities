import XCTest
import MurtenCore
@testable import RepoMenCore

/// A survey becomes an honest observation: scanned folders are completed scopes
/// with findings, refused ones are failures, never "nothing found".
final class StaleWatchReportTests: XCTestCase {

    private let home = "/Users/test"
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    func testScannedFoldersReportTheirTotals() throws {
        let settings = StaleWatchSettings(folders: [WatchedFolder(path: "/Users/test/dev", maxIdleDays: 14)])
        let observation = StaleWatchReport.observation(
            settings: settings,
            statuses: ["/Users/test/dev": .surveyed(StaleArtifactTotals(bytes: 7_000, count: 3))],
            at: date, home: home)

        XCTAssertEqual(observation.outcome, .complete)
        XCTAssertEqual(observation.completedScopes, [FindingScope("/Users/test/dev")])
        let finding = try XCTUnwrap(observation.findings.first)
        XCTAssertEqual(finding.condition, "stale-artifacts")
        XCTAssertEqual(finding.scope, FindingScope("/Users/test/dev"))
        XCTAssertEqual(finding.bytes("bytes"), 7_000)
        XCTAssertEqual(finding.count("count"), 3)
        XCTAssertEqual(finding.count("idleDays"), 14)
    }

    func testRefusedFoldersAreFailuresForTheirScope() {
        let settings = StaleWatchSettings(folders: [
            WatchedFolder(path: "/Users/test/Documents/GitHub"),
            WatchedFolder(path: "/Users/test/gone"),
            WatchedFolder(path: "/Users/test/locked"),
            WatchedFolder(path: "/Users/test/dev"),
        ])
        let observation = StaleWatchReport.observation(settings: settings, statuses: [
            "/Users/test/Documents/GitHub": .refused(.protected(root: "/Users/test/Documents")),
            "/Users/test/gone": .refused(.missing),
            "/Users/test/locked": .refused(.unreadable(permissionDenied: true, reason: "denied")),
            "/Users/test/dev": .surveyed(StaleArtifactTotals()),
        ], at: date, home: home)

        XCTAssertEqual(observation.outcome, .partial)
        XCTAssertEqual(observation.completedScopes, [FindingScope("/Users/test/dev")])
        let kinds = Dictionary(uniqueKeysWithValues: observation.failures.compactMap { failure in
            failure.scope.map { ($0.rawValue, failure.kind) }
        })
        XCTAssertEqual(kinds["/Users/test/Documents/GitHub"], .permissionDenied)
        XCTAssertEqual(kinds["/Users/test/gone"], .toolMissing)
        XCTAssertEqual(kinds["/Users/test/locked"], .permissionDenied)
        XCTAssertTrue(observation.failures.contains { $0.message.contains("scan it in Developer Cleanup") })
    }

    func testScanFoldersAreSurveyedWithThePanesIdleThreshold() throws {
        let settings = StaleWatchSettings(
            folders: [WatchedFolder(path: "/Users/test/dev", maxIdleDays: 7),
                      WatchedFolder(path: "/Users/test/old", isEnabled: false)],
            scanRoots: ["/Users/test/dev", "/Users/test/code", "/Users/test/old"], scanRootIdleDays: 45)

        XCTAssertEqual(settings.surveyedFolders,
                       [WatchedFolder(path: "/Users/test/dev", maxIdleDays: 7),
                        WatchedFolder(path: "/Users/test/code", maxIdleDays: 45)],
                       "a watched entry governs its path, paused or not")

        let observation = StaleWatchReport.observation(settings: settings, statuses: [
            "/Users/test/dev": .surveyed(StaleArtifactTotals(bytes: 1, count: 1)),
            "/Users/test/code": .surveyed(StaleArtifactTotals(bytes: 2, count: 1)),
        ], at: date, home: home)
        let code = try XCTUnwrap(observation.findings.first { $0.scope == FindingScope("/Users/test/code") })
        XCTAssertEqual(code.count("idleDays"), 45)
        XCTAssertEqual(observation.completedScopes.count, 2, "the paused folder is not surveyed")
    }

    func testDuplicateWatchedFoldersAreSurveyedOnce() {
        let settings = StaleWatchSettings(folders: [
            WatchedFolder(path: "/Users/test/dev", maxIdleDays: 7),
            WatchedFolder(path: "/Users/test/dev", maxIdleDays: 45),
        ])
        XCTAssertEqual(settings.surveyedFolders, [WatchedFolder(path: "/Users/test/dev", maxIdleDays: 7)],
                       "one path, one scope — the first entry wins")
    }

    func testScanRootNestedUnderAnEnabledWatchIsNotDoubleCounted() {
        let settings = StaleWatchSettings(
            folders: [WatchedFolder(path: "/Users/test/dev", maxIdleDays: 7)],
            scanRoots: ["/Users/test/dev/nested"], scanRootIdleDays: 45)
        XCTAssertEqual(settings.surveyedFolders.map(\.path), ["/Users/test/dev"],
                       "the watched folder's scan already covers the nested root")
    }

    func testScanRootNestedUnderADisabledWatchIsStillScanned() {
        let settings = StaleWatchSettings(
            folders: [WatchedFolder(path: "/Users/test/dev", isEnabled: false)],
            scanRoots: ["/Users/test/dev/nested"], scanRootIdleDays: 45)
        XCTAssertEqual(settings.surveyedFolders,
                       [WatchedFolder(path: "/Users/test/dev/nested", maxIdleDays: 45)],
                       "a paused watch must not shadow the pane's own scan folder")
    }

    func testRemovedOrPausedFoldersSuggestionsResolve() {
        let rule = StaleArtifactRule(home: home)
        var ledger = SuggestionLedger()
        let folders = [WatchedFolder(path: "/Users/test/dev"), WatchedFolder(path: "/Users/test/work")]
        let big = WatchRootStatus.surveyed(StaleArtifactTotals(bytes: 6_000_000_000, count: 2))
        _ = ledger.apply(StaleWatchReport.observation(
            settings: StaleWatchSettings(folders: folders),
            statuses: ["/Users/test/dev": big, "/Users/test/work": big], at: date, home: home), rule: rule)
        XCTAssertEqual(ledger.suggestions(at: date).count, 2)

        // dev removed, work paused: neither is listed any more.
        let later = StaleWatchReport.observation(
            settings: StaleWatchSettings(folders: [WatchedFolder(path: "/Users/test/work", isEnabled: false)]),
            statuses: [:], at: date.addingTimeInterval(60), home: home)
        XCTAssertEqual(later.coverage, .exhaustive)
        let events = ledger.apply(later, rule: rule)

        XCTAssertEqual(Set(events), [
            .resolved(SuggestionKey(moduleID: "repomen", condition: "stale-artifacts",
                                    scope: FindingScope("/Users/test/dev"))),
            .resolved(SuggestionKey(moduleID: "repomen", condition: "stale-artifacts",
                                    scope: FindingScope("/Users/test/work"))),
        ])
    }

    func testAFailedFolderKeepsItsSuggestion() {
        let rule = StaleArtifactRule(home: home)
        var ledger = SuggestionLedger()
        let settings = StaleWatchSettings(folders: [WatchedFolder(path: "/Users/test/dev")])
        _ = ledger.apply(StaleWatchReport.observation(
            settings: settings,
            statuses: ["/Users/test/dev": .surveyed(StaleArtifactTotals(bytes: 6_000_000_000, count: 2))],
            at: date, home: home), rule: rule)

        let failed = StaleWatchReport.observation(
            settings: settings, statuses: ["/Users/test/dev": .refused(.missing)], at: date, home: home)
        XCTAssertEqual(failed.outcome, .unavailable)
        XCTAssertTrue(failed.completedScopes.isEmpty, "a failed folder must not look checked")
        XCTAssertFalse(ledger.apply(failed, rule: rule).contains {
            if case .resolved = $0 { return true } else { return false }
        }, "could not look is not nothing found")
    }

    func testAStoppedSurveyIsAWholeCheckFailure() {
        let settings = StaleWatchSettings(folders: [WatchedFolder(path: "/Users/test/dev")])
        let observation = StaleWatchReport.observation(settings: settings, statuses: nil, at: date, home: home)

        XCTAssertEqual(observation.outcome, .unavailable)
        XCTAssertNil(observation.failures.first?.scope)
    }

    func testNoWatchedFoldersIsAQuietCompleteCheck() {
        let observation = StaleWatchReport.observation(settings: StaleWatchSettings(folders: []),
                                                       statuses: [:], at: date, home: home)
        XCTAssertEqual(observation.outcome, .complete)
        XCTAssertTrue(observation.findings.isEmpty)
    }
}
