import XCTest
import MurtenCore
@testable import RepoMenModule
@testable import RepoMenCore

/// The watcher against a fake survey: no file system, no clock, no suite.
final class StaleArtifactWatcherTests: XCTestCase {

    private struct FakeObserver: StaleArtifactObserving {
        let statuses: [String: WatchRootStatus]?
        let seen: Recorder

        func survey(_ settings: StaleWatchSettings, now: Date) async -> [String: WatchRootStatus]? {
            seen.record(settings)
            return statuses
        }
    }

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var settings: [StaleWatchSettings] = []

        func record(_ value: StaleWatchSettings) {
            lock.lock(); defer { lock.unlock() }
            settings.append(value)
        }

        var all: [StaleWatchSettings] {
            lock.lock(); defer { lock.unlock() }
            return settings
        }
    }

    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func watcher(_ statuses: [String: WatchRootStatus]?, settings: StaleWatchSettings,
                         recorder: Recorder = Recorder()) -> StaleArtifactWatcher {
        let date = self.date
        return StaleArtifactWatcher(observer: FakeObserver(statuses: statuses, seen: recorder),
                                    settings: { settings }, now: { date }, home: "/Users/test")
    }

    func testCadenceIsTheStandaloneIntervalWithAGenerousTimeout() {
        let cadence = StaleArtifactWatcher.defaultCadence
        XCTAssertEqual(cadence.interval, 6 * 3600)
        XCTAssertGreaterThanOrEqual(cadence.interval, WatchCadence.minimumInterval)
        XCTAssertGreaterThanOrEqual(cadence.timeout, 15 * 60)
        XCTAssertFalse(cadence.resources.contains(.network), "the check reads local folders only")
    }

    func testReportsEachWatchedFolderAsItsOwnScope() async {
        let settings = StaleWatchSettings(folders: [WatchedFolder(path: "/Users/test/dev"),
                                                    WatchedFolder(path: "/Users/test/Documents/GitHub")])
        let recorder = Recorder()
        let observation = await watcher([
            "/Users/test/dev": .surveyed(StaleArtifactTotals(bytes: 6_000_000_000, count: 4)),
            "/Users/test/Documents/GitHub": .refused(.protected(root: "/Users/test/Documents")),
        ], settings: settings, recorder: recorder).observe()

        XCTAssertEqual(observation.moduleID, "repomen")
        XCTAssertEqual(observation.observedAt, date)
        XCTAssertEqual(observation.findings.map(\.scope), [FindingScope("/Users/test/dev")])
        XCTAssertEqual(observation.failures.map(\.kind), [.permissionDenied])
        XCTAssertEqual(recorder.all, [settings], "one settings snapshot per poll")
    }

    func testFindingsTurnIntoSuggestionsThroughTheRule() async throws {
        let settings = StaleWatchSettings(folders: [WatchedFolder(path: "/Users/test/dev")])
        let observation = await watcher(
            ["/Users/test/dev": .surveyed(StaleArtifactTotals(bytes: 6_000_000_000, count: 4))],
            settings: settings).observe()
        let finding = try XCTUnwrap(observation.findings.first)

        let content = StaleArtifactRule(home: "/Users/test").suggestion(for: finding, state: .inactive)
        XCTAssertEqual(content?.route.action, "review")
    }

    func testCancelledSurveyIsReportedAsAFailure() async {
        let settings = StaleWatchSettings(folders: [WatchedFolder(path: "/Users/test/dev")])
        let observation = await watcher(nil, settings: settings).observe()
        XCTAssertEqual(observation.outcome, .unavailable)
    }
}
