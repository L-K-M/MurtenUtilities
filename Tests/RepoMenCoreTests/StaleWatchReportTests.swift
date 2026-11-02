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
        XCTAssertTrue(observation.failures.contains { $0.message.contains("scan it in RepoMen") })
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
        XCTAssertEqual(settings.unsurveyedPaths, ["/Users/test/old"])

        let observation = StaleWatchReport.observation(settings: settings, statuses: [
            "/Users/test/dev": .surveyed(StaleArtifactTotals(bytes: 1, count: 1)),
            "/Users/test/code": .surveyed(StaleArtifactTotals(bytes: 2, count: 1)),
        ], at: date, home: home)
        let code = try XCTUnwrap(observation.findings.first { $0.scope == FindingScope("/Users/test/code") })
        XCTAssertEqual(code.count("idleDays"), 45)
        XCTAssertEqual(observation.completedScopes.count, 3)
    }

    func testUnwatchedFoldersCountAsCheckedSoTheirSuggestionsResolve() {
        let settings = StaleWatchSettings(
            folders: [WatchedFolder(path: "/Users/test/paused", isEnabled: false)],
            retiredPaths: ["/Users/test/removed"])
        let observation = StaleWatchReport.observation(settings: settings, statuses: [:], at: date, home: home)

        XCTAssertEqual(observation.outcome, .complete)
        XCTAssertEqual(observation.completedScopes,
                       [FindingScope("/Users/test/paused"), FindingScope("/Users/test/removed")])
        XCTAssertTrue(observation.findings.isEmpty)
    }

    func testAnEnabledFolderIsNeverTreatedAsRetired() {
        let settings = StaleWatchSettings(folders: [WatchedFolder(path: "/Users/test/dev")],
                                          retiredPaths: ["/Users/test/dev"])
        let observation = StaleWatchReport.observation(
            settings: settings, statuses: ["/Users/test/dev": .refused(.missing)], at: date, home: home)

        XCTAssertEqual(observation.outcome, .unavailable)
        XCTAssertTrue(observation.completedScopes.isEmpty, "a failed folder must not look checked")
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
