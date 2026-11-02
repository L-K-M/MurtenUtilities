import XCTest
@testable import RepoMenModule
@testable import RepoMenCore

/// What the background check reads from the settings, and how removed folders
/// are remembered so their suggestions can resolve.
final class WatchSettingsSnapshotTests: XCTestCase {

    private func makePreferences() -> (Preferences, UserDefaults) {
        let name = "RepoMenWatchSnapshotTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        defaults.set([String](), forKey: "scanRoots")
        return (Preferences(defaults: defaults), defaults)
    }

    func testRemovedFoldersAreRetiredUntilWatchedAgain() {
        let (preferences, defaults) = makePreferences()
        preferences.watchFolder(path: "/Users/x/dev")
        preferences.watchFolder(path: "/Users/x/work")

        preferences.watchedFolders.removeAll { $0.path == "/Users/x/dev" }
        XCTAssertEqual(preferences.watchSettings.retiredPaths, ["/Users/x/dev"])
        XCTAssertEqual(Preferences(defaults: defaults).watchSettings.retiredPaths, ["/Users/x/dev"],
                       "retired folders persist across launches")

        preferences.watchFolder(path: "/Users/x/dev")
        XCTAssertTrue(preferences.watchSettings.retiredPaths.isEmpty)
    }

    func testRemovedScanFoldersAreRetiredToo() {
        let (preferences, _) = makePreferences()
        preferences.scanRoots = ["/Users/x/code", "/Users/x/dev"]
        preferences.watchFolder(path: "/Users/x/dev")

        preferences.scanRoots = []
        XCTAssertEqual(preferences.watchSettings.retiredPaths, ["/Users/x/code"],
                       "a path still watched is not retired")
    }

    func testRetiredFoldersAreBounded() {
        let (preferences, _) = makePreferences()
        for index in 0..<(Preferences.retiredWatchFolderLimit + 5) {
            preferences.watchFolder(path: "/Users/x/\(index)")
            preferences.watchedFolders = []
        }
        XCTAssertEqual(preferences.watchSettings.retiredPaths.count, Preferences.retiredWatchFolderLimit)
        XCTAssertEqual(preferences.watchSettings.retiredPaths.last,
                       "/Users/x/\(Preferences.retiredWatchFolderLimit + 4)")
    }

    func testSnapshotCarriesFoldersExclusionsAndEnabledKinds() {
        let (preferences, _) = makePreferences()
        preferences.scanRoots = ["/Users/x/code"]
        preferences.idleDays = 21
        preferences.excludedPaths = ["/Users/x/dev/keep"]
        preferences.setEnabled(false, kind: .nodeModules)

        let settings = preferences.watchSettings
        XCTAssertEqual(settings.scanRoots, ["/Users/x/code"])
        XCTAssertEqual(settings.scanRootIdleDays, 21)
        XCTAssertEqual(settings.excludedPaths, ["/Users/x/dev/keep"])
        XCTAssertFalse(settings.enabledKinds.contains(.nodeModules))
        XCTAssertTrue(settings.enabledKinds.contains(.rustTarget))
    }

    func testAutoTrashLogRoundTrips() {
        let (preferences, defaults) = makePreferences()
        let entry = AutoTrashLogEntry(date: Date(timeIntervalSince1970: 1_800_000_000), path: "/Users/x/dev/a/target",
                                      label: "a/target", bytes: 42, result: .skipped(reason: "its anchor is gone"))
        preferences.autoTrashLog = [entry]
        XCTAssertEqual(Preferences(defaults: defaults).autoTrashLog, [entry])
    }
}
