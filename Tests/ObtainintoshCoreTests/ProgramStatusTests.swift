import XCTest
@testable import ObtainintoshCore

final class ProgramStatusTests: XCTestCase {
    private func app(current: String? = nil, latest: String? = nil, checked: Bool = true,
                     attempt: CheckAttemptState? = nil, message: String? = nil,
                     downloaded: String? = nil) -> TrackedApp {
        TrackedApp(id: "id", name: "Tool", sourceType: .github, sourceURL: "https://github.com/o/tool",
                   currentVersion: current, latestVersion: latest, lastChecked: checked ? "2026-09-05T00:00:00Z" : nil,
                   lastCheckAttempt: attempt.map { CheckAttempt(attemptedAt: "t", state: $0, message: message) },
                   downloaded: downloaded.map { DownloadedRelease(version: $0, path: "/tmp/Tool.dmg") })
    }

    func testStatusFollowsTheRowsPrecedence() {
        XCTAssertEqual(ProgramStatus(app(attempt: .unsupported)).label, "Unsupported")
        XCTAssertEqual(ProgramStatus(app(attempt: .unsupported)).help, "This source cannot be checked for updates.")
        XCTAssertEqual(ProgramStatus(app(latest: "2.0", attempt: .failed)).label, "Check Failed (Stale)")
        XCTAssertEqual(ProgramStatus(app(attempt: .failed)).label, "Check Failed")
        XCTAssertEqual(ProgramStatus(app(current: "1.0", latest: "2.0")), .updateAvailable)
        XCTAssertEqual(ProgramStatus(app(current: "1.0", checked: false)), .notChecked)
        XCTAssertEqual(ProgramStatus(app(current: "1.0")), .notFound)
        XCTAssertEqual(ProgramStatus(app(current: "2.0", latest: "2.0")), .upToDate)
        XCTAssertEqual(ProgramStatus(app(latest: "2.0")), .notInstalled)
    }

    func testAFailedCheckSaysWhetherTheVersionShownIsOlder() {
        XCTAssertEqual(ProgramStatus(app(latest: "2.0", attempt: .failed, message: "offline.")).help,
                       "Last update check failed: offline. The latest version shown is from an earlier successful check.")
        XCTAssertEqual(ProgramStatus(app(attempt: .failed)).help,
                       "Last update check failed: The update check did not complete.")
    }

    func testActionFollowsTheRowsPrecedence() {
        XCTAssertEqual(ProgramAction(app(current: "1.0", latest: "2.0", downloaded: "2.0")), .revealDownload)
        // A cached older version gives way to the download of the newer one.
        XCTAssertEqual(ProgramAction(app(current: "1.0", latest: "2.1", downloaded: "2.0")), .downloadUpdate)
        XCTAssertEqual(ProgramAction(app(latest: "2.0")), .download)
        XCTAssertEqual(ProgramAction(app(current: "2.0", latest: "2.0")), .none)
    }

    func testSortingByStatusPutsUpdatesFirstAndTiesByName() {
        let apps = [
            TrackedApp(id: "c", name: "Charlie", sourceType: .github, sourceURL: "c", currentVersion: "1", latestVersion: "1"),
            TrackedApp(id: "a", name: "alpha", sourceType: .github, sourceURL: "a", currentVersion: "1", latestVersion: "2"),
            TrackedApp(id: "b", name: "Bravo", sourceType: .github, sourceURL: "b"),
            TrackedApp(id: "d", name: "delta", sourceType: .github, sourceURL: "d", latestVersion: "1"),
        ]
        var sort = ProgramSort()
        XCTAssertEqual(sort.sorted(apps).map(\.id), ["a", "b", "c", "d"])

        sort.select(.status)
        XCTAssertEqual(sort.sorted(apps).map(\.id), ["a", "b", "c", "d"])
        sort.select(.status)
        XCTAssertFalse(sort.ascending)
        XCTAssertEqual(sort.sorted(apps).map(\.id), ["d", "c", "b", "a"])

        sort.select(.latest)
        XCTAssertTrue(sort.ascending)
        // Unknown first, then by version, ties by name.
        XCTAssertEqual(sort.sorted(apps).map(\.id), ["b", "c", "d", "a"])
    }
}
