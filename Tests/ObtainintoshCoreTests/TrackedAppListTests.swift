import XCTest
@testable import ObtainintoshCore

/// The standalone app's storage rules (dedupe, ids, edits, check results),
/// tested on the pure list the suite's store wraps. File behaviour is tested
/// with the store in ObtainintoshServicesTests.
final class TrackedAppListTests: XCTestCase {
    private func app(_ id: String, _ url: String) -> TrackedApp {
        TrackedApp(id: id, name: id, sourceType: .github, sourceURL: url)
    }

    private func hauntware(_ id: String, _ program: String?) -> TrackedApp {
        var app = app(id, "https://github.com/L-K-M/Hauntware")
        app.assetFilter = program
        return app
    }

    private func list(_ apps: [TrackedApp]) -> TrackedAppList {
        TrackedAppList(data: TrackedAppData(apps: apps))
    }

    private func counter() -> () -> String {
        var next = 0
        return {
            next += 1
            return "generated-\(next)"
        }
    }

    private let succeeded = CheckOwnedUpdate(currentVersion: "1.0.0", installPath: "/Applications/Existing.app",
                                             latestVersion: "2.0.0",
                                             attempt: .succeeded(at: "2026-08-06T00:00:00Z"))

    private func succeeded(_ latest: String) -> CheckOwnedUpdate {
        var update = succeeded
        update.latestVersion = latest
        return update
    }

    private let failed = CheckOwnedUpdate(currentVersion: "1.0.0", installPath: "/Applications/Existing.app",
                                          latestVersion: nil,
                                          attempt: .unsuccessful(at: "2026-08-06T00:00:00Z", state: .failed,
                                                                 message: "the network went away"))

    // MARK: - Adding

    func testBatchAddSkipsTrackedRepositories() {
        var tracked = list([app("existing", "https://github.com/owner/existing")])

        let addition = tracked.add([
            // Same repository as the stored one, spelled differently.
            app("", "https://GitHub.com/owner/existing.git"),
            app("", "https://github.com/owner/new"),
            // Repeated within the batch: the first occurrence wins.
            app("", "https://github.com/owner/new/"),
            app("", "https://github.com/owner/other"),
        ], makeID: counter())

        XCTAssertEqual(addition.added.map(\.sourceURL), ["https://github.com/owner/new", "https://github.com/owner/other"])
        XCTAssertTrue(addition.added.allSatisfy { !$0.id.isEmpty })
        XCTAssertNotEqual(addition.added[0].id, addition.added[1].id)
        XCTAssertEqual(addition.duplicates.map(\.sourceURL),
                       ["https://GitHub.com/owner/existing.git", "https://github.com/owner/new/"])
        XCTAssertEqual(tracked.apps.map(\.id), ["existing", addition.added[0].id, addition.added[1].id])
    }

    func testBatchAddKeepsIDsUnique() {
        var tracked = list([app("taken", "https://github.com/owner/existing")])

        let addition = tracked.add([
            // Collides with the stored entry's id.
            app("taken", "https://github.com/owner/one"),
            // Collides with the entry just above, within the batch.
            app("taken", "https://github.com/owner/two"),
            // A free id is kept as given.
            app("free", "https://github.com/owner/three"),
        ])

        let ids = tracked.apps.map(\.id)
        XCTAssertEqual(ids.count, 4)
        XCTAssertEqual(Set(ids).count, 4, "ids were not unique")
        XCTAssertTrue(ids.contains("taken"))
        XCTAssertEqual(addition.added[2].id, "free")
        XCTAssertNotEqual(addition.added[0].id, "taken")
        XCTAssertNotEqual(addition.added[1].id, addition.added[0].id)
    }

    func testBatchAddWithNothingNewChangesNothing() {
        var tracked = list([app("existing", "https://github.com/owner/existing")])
        let before = tracked

        let addition = tracked.add([app("", "https://github.com/owner/existing")])

        XCTAssertTrue(addition.added.isEmpty)
        XCTAssertEqual(addition.duplicates.count, 1)
        XCTAssertEqual(tracked, before)
    }

    func testEachProgramOfARepositoryIsTrackedOnce() throws {
        var tracked = list([])
        for program in ["seance", "planchette", nil] {
            _ = try tracked.addOne(hauntware("", program))
        }

        XCTAssertThrowsError(try tracked.addOne(hauntware("", "seance"))) {
            XCTAssertEqual("\($0)", "\"seance\" from this repository is already being tracked")
        }
        XCTAssertThrowsError(try tracked.addOne(hauntware("", nil))) {
            XCTAssertEqual("\($0)", "This repository is already being tracked")
        }
        XCTAssertEqual(tracked.apps.count, 3)
    }

    func testHandEditedFiltersAreComparedInCanonicalForm() {
        var tracked = list([hauntware("capitalised", "Seance"), hauntware("blank", "")])
        XCTAssertThrowsError(try tracked.addOne(hauntware("", "seance")), "\"Seance\" and \"seance\" are one program")
        XCTAssertThrowsError(try tracked.addOne(hauntware("", nil)), "an empty filter is no filter")
    }

    // MARK: - Editing

    func testAnEditCannotMakeAnEntryTrackWhatAnotherOneDoes() throws {
        var tracked = list([hauntware("seance", "seance"), hauntware("planchette", "planchette")])

        var retargeted = hauntware("planchette", "seance")
        XCTAssertThrowsError(try tracked.update(retargeted)) {
            XCTAssertEqual("\($0)", "\"seance\" from this repository is already being tracked")
        }
        XCTAssertEqual(tracked.app(id: "planchette")?.assetFilter, "planchette")

        retargeted.assetFilter = "poltergeist"
        XCTAssertNoThrow(try tracked.update(retargeted))
    }

    func testEntriesThatAlreadyCollideStayEditable() throws {
        // Edits were not checked before, so a file can hold two entries for the same repository.
        var tracked = list([app("first", "https://github.com/owner/same"), app("second", "https://github.com/owner/same")])

        var renamed = try XCTUnwrap(tracked.app(id: "second"))
        renamed.name = "Renamed"
        try tracked.update(renamed)

        XCTAssertEqual(tracked.app(id: "second")?.name, "Renamed")
    }

    func testRemovingRemembersTheIDBoundedAndReAddingForgetsIt() {
        var tracked = list([app("a", "https://github.com/owner/a")])
        tracked.remove(id: "a")
        tracked.remove(id: "unknown")
        XCTAssertTrue(tracked.apps.isEmpty)
        XCTAssertEqual(tracked.data.removedAppIDs, ["a"])

        _ = tracked.add([app("a", "https://github.com/owner/a")])
        XCTAssertTrue(tracked.data.removedAppIDs.isEmpty)

        for index in 0..<(TrackedAppData.removedIDLimit + 5) {
            _ = tracked.add([app("x\(index)", "https://github.com/owner/x\(index)")])
            tracked.remove(id: "x\(index)")
        }
        XCTAssertEqual(tracked.data.removedAppIDs.count, TrackedAppData.removedIDLimit)
        XCTAssertEqual(tracked.data.removedAppIDs.last, "x\(TrackedAppData.removedIDLimit + 4)")
    }

    func testForgetDownloadsClearsOnlyTheNamedApps() {
        var gone = app("gone", "https://github.com/owner/gone")
        gone.downloaded = DownloadedRelease(version: "1.0", path: "/tmp/nowhere/App.dmg")
        var kept = app("kept", "https://github.com/owner/kept")
        kept.downloaded = DownloadedRelease(version: "2.0", path: "/tmp/still-there/App.dmg")
        var tracked = list([gone, kept])

        XCTAssertEqual(tracked.forgetDownloads(["gone", "unknown"]), 1)
        XCTAssertNil(tracked.app(id: "gone")?.downloaded)
        XCTAssertEqual(tracked.app(id: "kept")?.downloaded, DownloadedRelease(version: "2.0", path: "/tmp/still-there/App.dmg"))
        // Nothing left to clear, so no count lies.
        XCTAssertEqual(tracked.forgetDownloads(["gone"]), 0)
    }

    // MARK: - Check results

    func testASuccessfulCheckRecordsItsVersionAndTimestamp() throws {
        let snapshot = app("existing", "https://github.com/owner/existing")
        var tracked = list([snapshot])

        XCTAssertEqual(tracked.applyCheckResult(snapshot: snapshot, update: succeeded("2.0.0")), .applied)

        let stored = try XCTUnwrap(tracked.app(id: "existing"))
        XCTAssertEqual(stored.latestVersion, "2.0.0")
        XCTAssertEqual(stored.lastChecked, "2026-08-06T00:00:00Z")
        XCTAssertEqual(stored.lastCheckAttempt?.state, .succeeded)
    }

    func testAFailedCheckKeepsTheLastKnownVersionAndMarksItStale() throws {
        var tracked = list([app("existing", "https://github.com/owner/existing")])
        _ = tracked.applyCheckResult(snapshot: try XCTUnwrap(tracked.app(id: "existing")), update: succeeded("2.0.0"))

        _ = tracked.applyCheckResult(snapshot: try XCTUnwrap(tracked.app(id: "existing")), update: failed)

        let stored = try XCTUnwrap(tracked.app(id: "existing"))
        XCTAssertEqual(stored.latestVersion, "2.0.0")
        XCTAssertEqual(stored.lastChecked, "2026-08-06T00:00:00Z")
        XCTAssertEqual(stored.lastCheckAttempt?.state, .failed)
        XCTAssertEqual(stored.lastCheckAttempt?.message, "the network went away")
    }

    func testAResultForARemovedAppIsNotWrittenBack() {
        let snapshot = app("existing", "https://github.com/owner/existing")
        var tracked = list([snapshot])
        tracked.remove(id: "existing")

        XCTAssertEqual(tracked.applyCheckResult(snapshot: snapshot, update: succeeded("2.0.0")), .appRemoved)
        XCTAssertNil(tracked.app(id: "existing"))
    }

    func testAResultDoesNotOverwriteAnEditMadeWhileItRan() throws {
        let snapshot = app("existing", "https://github.com/owner/existing")
        var tracked = list([snapshot])
        var renamed = snapshot
        renamed.name = "Renamed"
        try tracked.update(renamed)

        XCTAssertEqual(tracked.applyCheckResult(snapshot: snapshot, update: succeeded("2.0.0")), .dependenciesChanged)
        XCTAssertEqual(tracked.app(id: "existing")?.name, "Renamed")
        XCTAssertNil(tracked.app(id: "existing")?.latestVersion)
    }

    func testAnOlderResultLosesToOneThatAlreadyLanded() {
        let snapshot = app("existing", "https://github.com/owner/existing")
        var tracked = list([snapshot])
        _ = tracked.applyCheckResult(snapshot: snapshot, update: succeeded("3.0.0"))

        // The stale snapshot still has no latest version, so its result is the older one.
        XCTAssertEqual(tracked.applyCheckResult(snapshot: snapshot, update: succeeded("2.0.0")), .dependenciesChanged)
        XCTAssertEqual(tracked.app(id: "existing")?.latestVersion, "3.0.0")
    }

    func testAResultForAnotherProgramOfTheRepositoryIsNotWrittenBack() throws {
        let snapshot = app("existing", "https://github.com/owner/existing")
        var tracked = list([snapshot])
        var refiltered = snapshot
        refiltered.assetFilter = "seance"
        try tracked.update(refiltered)

        XCTAssertEqual(tracked.applyCheckResult(snapshot: snapshot, update: succeeded("2.0.0")), .dependenciesChanged)
        XCTAssertNil(tracked.app(id: "existing")?.latestVersion)
    }

    func testCheckOwnedUpdatesFromLookupResults() {
        let installed = InstalledVersion(path: "/Applications/Tool.app", version: "1.0")
        let release = Release(version: "2.0", downloadURL: "u", fileName: "Tool.dmg", fileSize: 1)

        let success = CheckOwnedUpdate.from(installed: installed, sourceType: .github, result: .success(release),
                                            attemptedAt: "t")
        XCTAssertEqual(success.latestVersion, "2.0")
        XCTAssertEqual(success.currentVersion, "1.0")
        XCTAssertEqual(success.attempt.state, .succeeded)

        let failure = CheckOwnedUpdate.from(installed: nil, sourceType: .github,
                                            result: .failure(ObtainintoshError("offline")), attemptedAt: "t")
        XCTAssertNil(failure.latestVersion)
        XCTAssertEqual(failure.attempt.state, .failed)
        XCTAssertEqual(failure.attempt.message, "offline")

        let gitLab = CheckOwnedUpdate.from(installed: nil, sourceType: .gitlab,
                                           result: .failure(ObtainintoshError("GitLab support not yet implemented")),
                                           attemptedAt: "t")
        XCTAssertEqual(gitLab.attempt.state, .unsupported)
    }
}
