import XCTest
@testable import RepoMenModule
@testable import RepoMenCore

/// Armed auto-trash against a fake survey and a fake Trash: what runs, when it
/// refuses, and what it records. Nothing here touches the real disk.
@MainActor
final class AutoTrashControllerTests: XCTestCase {

    private final class Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func makePreferences() -> Preferences {
        let name = "RepoMenAutoTrashTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        defaults.set([String](), forKey: "scanRoots")
        return Preferences(defaults: defaults)
    }

    private func item(_ path: String, bytes: Int64) -> CleanableItem {
        CleanableItem(label: "app/target", kind: .rustTarget, path: path, anchorPaths: [],
                      isKnownCache: false, sizeBytes: bytes, isMeasured: true)
    }

    func testDoesNothingWhileBackgroundWorkIsNotAllowed() async {
        let preferences = makePreferences()
        preferences.watchedFolders = [WatchedFolder(path: "/w/dev", autoTrashArmed: true)]
        let collected = Box(0)
        let controller = AutoTrashController(
            preferences: preferences, backgroundWorkAllowed: { false },
            collector: { _, _, _ in collected.value += 1; return [:] },
            trasher: { _ in XCTFail("nothing may be trashed"); return [] },
            protectedRoots: [])

        await controller.runPass()

        XCTAssertEqual(collected.value, 0, "not even a scan without the suite's consent")
        XCTAssertNil(preferences.lastWatchRun)
    }

    func testTrashesOnlyArmedFoldersStaleItemsAndLogsThem() async {
        let preferences = makePreferences()
        preferences.watchedFolders = [WatchedFolder(path: "/w/dev", autoTrashArmed: true),
                                      WatchedFolder(path: "/w/dev/keep"),
                                      WatchedFolder(path: "/w/other")]
        let first = item("/w/dev/a/target", bytes: 300)
        let second = item("/w/dev/b/target", bytes: 200)
        let kept = item("/w/dev/keep/c/target", bytes: 900)
        let scannedRoots = Box<[String]>([])
        let trashed = Box<[String]>([])
        let rechecks = Box(0)
        let date = self.date
        let controller = AutoTrashController(
            preferences: preferences, backgroundWorkAllowed: { true },
            didTrash: { rechecks.value += 1 },
            collector: { roots, _, _ in
                scannedRoots.value = roots.map(\.path)
                return ["/w/dev": [second, first], "/w/dev/keep": [kept]]
            },
            trasher: { items in
                trashed.value = items.map(\.path)
                return [Reclaimer.Outcome(item: items[0], failure: nil),
                        Reclaimer.Outcome(item: items[1], failure: "its anchor is gone")]
            },
            protectedRoots: [], now: { date })

        await controller.runPass()

        XCTAssertEqual(scannedRoots.value, ["/w/dev"], "only armed folders are scanned")
        XCTAssertEqual(trashed.value, ["/w/dev/a/target", "/w/dev/b/target"],
                       "the unarmed nested folder keeps its items")
        XCTAssertEqual(preferences.autoTrashLog.map(\.result), [.trashed, .skipped(reason: "its anchor is gone")])
        XCTAssertEqual(preferences.lastWatchRun, WatchRunRecord(
            date: date, dryRun: false, candidateCount: 2, candidateBytes: 500,
            reclaimedCount: 1, reclaimedBytes: 300, failureCount: 1))
        XCTAssertEqual(preferences.lifetimeReclaimedBytes, 300)
        XCTAssertEqual(rechecks.value, 1, "the background check re-runs so the suggestion can resolve")
        XCTAssertFalse(controller.isRunning)
    }

    func testStopsBeforeTrashingWhenConsentEndsDuringTheScan() async {
        let preferences = makePreferences()
        preferences.watchedFolders = [WatchedFolder(path: "/w/dev", autoTrashArmed: true)]
        let allowed = Box(true)
        let candidate = item("/w/dev/a/target", bytes: 300)
        let controller = AutoTrashController(
            preferences: preferences, backgroundWorkAllowed: { allowed.value },
            collector: { _, _, _ in
                allowed.value = false   // resident mode switched off mid-scan
                return ["/w/dev": [candidate]]
            },
            trasher: { _ in XCTFail("nothing may be trashed"); return [] },
            protectedRoots: [])

        await controller.runPass()

        XCTAssertNil(preferences.lastWatchRun)
        XCTAssertTrue(preferences.autoTrashLog.isEmpty)
    }

    func testArmedProtectedFoldersNeverRun() async {
        let preferences = makePreferences()
        preferences.watchedFolders = [WatchedFolder(path: "/w/Documents/code", autoTrashArmed: true)]
        let collected = Box(0)
        let controller = AutoTrashController(
            preferences: preferences, backgroundWorkAllowed: { true },
            collector: { _, _, _ in collected.value += 1; return [:] },
            trasher: { _ in [] },
            protectedRoots: ["/w/Documents"])

        await controller.runPass()

        XCTAssertEqual(collected.value, 0)
        XCTAssertTrue(controller.isProtected(preferences.watchedFolders[0]))
    }

    func testScheduleExistsOnlyWhileAFolderIsArmed() async throws {
        let preferences = makePreferences()
        preferences.watchedFolders = [WatchedFolder(path: "/w/dev")]
        let sleeps = Box<[TimeInterval]>([])
        let date = self.date
        let controller = AutoTrashController(
            preferences: preferences, backgroundWorkAllowed: { true },
            collector: { _, _, _ in [:] }, trasher: { _ in [] },
            protectedRoots: [], now: { date },
            sleep: { seconds in
                sleeps.value.append(seconds)
                try await Task.sleep(nanoseconds: 60_000_000_000)
            })
        controller.start()
        defer { controller.stop() }

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(sleeps.value.isEmpty, "nothing armed, nothing scheduled")

        preferences.watchedFolders[0].autoTrashArmed = true
        let scheduled = await eventually { sleeps.value.count == 1 }
        XCTAssertTrue(scheduled)
        XCTAssertEqual(sleeps.value.first, AutoTrash.initialDelay)

        controller.disarmAll()
        XCTAssertFalse(preferences.watchedFolders[0].autoTrashArmed)
        XCTAssertTrue(controller.armedFolders.isEmpty)
    }

    private func eventually(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }
}
