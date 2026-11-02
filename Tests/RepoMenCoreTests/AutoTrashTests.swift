import XCTest
@testable import RepoMenCore

/// The pure decisions behind user-armed auto-trash.
final class AutoTrashTests: XCTestCase {

    private let protectedRoots = ProtectedLocations.roots(home: "/Users/test")

    private func item(_ path: String, bytes: Int64 = 100) -> CleanableItem {
        CleanableItem(label: URL(fileURLWithPath: path).lastPathComponent, kind: .rustTarget, path: path,
                      anchorPaths: [], isKnownCache: false, sizeBytes: bytes, isMeasured: true)
    }

    func testOnlyArmedEnabledUnprotectedFoldersRun() {
        let folders = [
            WatchedFolder(path: "/Users/test/dev", autoTrashArmed: true),
            WatchedFolder(path: "/Users/test/work"),
            WatchedFolder(path: "/Users/test/paused", isEnabled: false, autoTrashArmed: true),
            WatchedFolder(path: "/Users/test/Documents/GitHub", autoTrashArmed: true),
        ]
        let runnable = AutoTrash.runnableFolders(folders, protectedRoots: protectedRoots, readLink: { _ in nil })
        XCTAssertEqual(runnable.map(\.path), ["/Users/test/dev"])
    }

    func testCandidatesComeOnlyFromArmedFolders() {
        let stale = [
            "/Users/test/dev": [item("/Users/test/dev/b/target"), item("/Users/test/dev/a/target")],
            "/Users/test/dev/keep": [item("/Users/test/dev/keep/x/target")],
        ]
        let candidates = AutoTrash.candidates(staleByRoot: stale, armedPaths: ["/Users/test/dev"])
        XCTAssertEqual(candidates.map(\.path), ["/Users/test/dev/a/target", "/Users/test/dev/b/target"],
                       "an unarmed nested folder keeps its items; order is deterministic")
    }

    func testNextRunWaitsAnIntervalAfterTheLastPass() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(AutoTrash.nextRun(lastRun: nil, earliest: now), now)
        XCTAssertEqual(AutoTrash.nextRun(lastRun: now.addingTimeInterval(-3600), earliest: now),
                       now.addingTimeInterval(5 * 3600))
        XCTAssertEqual(AutoTrash.nextRun(lastRun: now.addingTimeInterval(-7 * 3600), earliest: now), now)
    }

    func testLogKeepsNewestFirstAndIsBounded() {
        let old = (0..<5).map {
            AutoTrashLogEntry(date: Date(timeIntervalSince1970: Double($0)), path: "/old/\($0)", label: "old",
                              bytes: 1, result: .trashed)
        }
        let outcomes = [Reclaimer.Outcome(item: item("/Users/test/dev/a/target", bytes: 10), failure: nil),
                        Reclaimer.Outcome(item: item("/Users/test/dev/b/target", bytes: 20), failure: "its anchor is gone")]
        let fresh = AutoTrash.entries(for: outcomes, at: Date(timeIntervalSince1970: 100))

        let log = AutoTrash.appending(fresh, to: old, limit: 4)

        XCTAssertEqual(log.count, 4)
        XCTAssertEqual(log.first?.date, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(fresh.map(\.result), [.trashed, .skipped(reason: "its anchor is gone")])
    }

    func testRecordCountsOnlyWhatWasTrashed() {
        let candidates = [item("/a", bytes: 10), item("/b", bytes: 20)]
        let outcomes = [Reclaimer.Outcome(item: candidates[0], failure: nil),
                        Reclaimer.Outcome(item: candidates[1], failure: "refused")]
        let record = AutoTrash.record(candidates: candidates, outcomes: outcomes, at: Date())

        XCTAssertFalse(record.dryRun)
        XCTAssertEqual(record.candidateBytes, 30)
        XCTAssertEqual(record.reclaimedCount, 1)
        XCTAssertEqual(record.reclaimedBytes, 10)
        XCTAssertEqual(record.failureCount, 1)
    }

    func testStandaloneWatchedFoldersDecodeUnarmed() throws {
        // Saved by the standalone app, which had no per-folder arming.
        let json = Data(#"[{"path":"/Users/test/dev","maxIdleDays":21,"isEnabled":true}]"#.utf8)
        let folders = try JSONDecoder().decode([WatchedFolder].self, from: json)
        XCTAssertEqual(folders, [WatchedFolder(path: "/Users/test/dev", maxIdleDays: 21)])
        XCTAssertFalse(folders[0].autoTrashArmed)

        let armed = WatchedFolder(path: "/Users/test/dev", autoTrashArmed: true)
        let roundTrip = try JSONDecoder().decode(WatchedFolder.self, from: JSONEncoder().encode(armed))
        XCTAssertEqual(roundTrip, armed)
    }
}
