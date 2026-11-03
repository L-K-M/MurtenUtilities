import XCTest
@testable import RepoMenModule
@testable import RepoMenCore

/// The one-time import of the standalone app's settings, from a fixture
/// dictionary rather than the real `ch.lkmc.RepoMen` domain.
final class StandalonePreferencesImportTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let name = "RepoMenImportTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private let watchedJSON = Data(#"[{"path":"/Users/x/dev","maxIdleDays":14,"isEnabled":true}]"#.utf8)

    private var standalone: [String: Any] {
        [
            "scanRoots": ["/Users/x/dev"],
            "excludedPaths": ["/Users/x/dev/keep/target"],
            "moveToTrash": false,
            "idleDays": 45,
            "disabledKinds": ["pythonVenv"],
            "lifetimeReclaimedBytes": 12_000,
            "lifetimeReclaimedCount": 3,
            "watchedFolders": watchedJSON,
            "scanAtLaunch": true,
            // Never imported:
            "watchAutoTrash": true,
            "showInMenuBar": true,
            "launchAtLogin": true,
            "lastWatchDryRunSignature": "x",
            "UpdateChecker.L-K-M.RepoMen.enabled": true,
        ]
    }

    func testCarriesSettingsOverButNeverArmsAutoTrash() {
        let suite = freshDefaults()
        StandalonePreferencesImport.importOnce(from: standalone, into: suite)
        let preferences = Preferences(defaults: suite)

        XCTAssertEqual(preferences.scanRoots, ["/Users/x/dev"])
        XCTAssertEqual(preferences.excludedPaths, ["/Users/x/dev/keep/target"])
        XCTAssertFalse(preferences.moveToTrash)
        XCTAssertEqual(preferences.idleDays, 45)
        XCTAssertFalse(preferences.isEnabled(.pythonVenv))
        XCTAssertEqual(preferences.lifetimeReclaimedBytes, 12_000)
        XCTAssertTrue(preferences.scanAtLaunch)
        XCTAssertEqual(preferences.watchedFolders, [WatchedFolder(path: "/Users/x/dev", maxIdleDays: 14)])
        XCTAssertFalse(preferences.watchedFolders[0].autoTrashArmed,
                       "the standalone watchAutoTrash switch is not imported as armed")
        for key in ["watchAutoTrash", "showInMenuBar", "launchAtLogin", "lastWatchDryRunSignature",
                    "UpdateChecker.L-K-M.RepoMen.enabled"] {
            XCTAssertNil(suite.object(forKey: key), key)
        }
    }

    func testRunsOnceAndNeverOverwritesTheSuitesOwnSettings() {
        let suite = freshDefaults()
        suite.set(10, forKey: "idleDays")

        StandalonePreferencesImport.importOnce(from: standalone, into: suite)
        XCTAssertEqual(suite.integer(forKey: "idleDays"), 10, "the suite's own value wins")

        suite.removeObject(forKey: "scanRoots")
        StandalonePreferencesImport.importOnce(from: standalone, into: suite)
        XCTAssertNil(suite.object(forKey: "scanRoots"), "a second launch imports nothing")
    }

    func testWithoutAStandaloneAppTheImportIsStillDone() {
        let suite = freshDefaults()
        StandalonePreferencesImport.importOnce(from: [:], into: suite)
        StandalonePreferencesImport.importOnce(from: standalone, into: suite)
        XCTAssertNil(suite.object(forKey: "scanRoots"))
    }
}
