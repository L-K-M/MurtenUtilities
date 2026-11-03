import XCTest
@testable import RunningManCore

/// The one-time import of the standalone app's preferences, against scratch defaults
/// suites standing in for the standalone domain and the module's store.
final class StandalonePreferencesTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() {
        for name in suites { UserDefaults().removePersistentDomain(forName: name) }
        suites = []
    }

    func testOfferListsCleanedFoldersAndServersWhenTheModuleStoreIsEmpty() throws {
        let standalone = scratch("standalone"), module = scratch("module")
        standalone.set(["/Users/example/runners/a", "relative/b", "/Users/example/runners/a", "/Volumes/CI/c"],
                       forKey: StandalonePreferences.Key.runnerDirectories)
        standalone.set(["https://forge.example.com", "http://plain.example.com", "https://user:secret@forge.example.org"],
                       forKey: StandalonePreferences.Key.forgejoServers)
        standalone.set("https://forge.example.com", forKey: StandalonePreferences.Key.defaultForgejoServer)

        let offer = try XCTUnwrap(StandalonePreferences.offer(standalone: standalone, module: module))

        XCTAssertEqual(offer.runnerDirectories, ["/Users/example/runners/a", "/Volumes/CI/c"])
        XCTAssertEqual(offer.forgejoServers, ["https://forge.example.com"])
        XCTAssertEqual(offer.defaultForgejoServer, "https://forge.example.com")
    }

    func testNoOfferWithoutStandaloneDataOrOnceTheModuleHasItsOwn() {
        let standalone = scratch("standalone"), module = scratch("module")
        XCTAssertNil(StandalonePreferences.offer(standalone: nil, module: module))
        XCTAssertNil(StandalonePreferences.offer(standalone: standalone, module: module), "Nothing to import")

        standalone.set(["/Users/example/runners/a"], forKey: StandalonePreferences.Key.runnerDirectories)
        module.set(["https://forge.example.com"], forKey: StandalonePreferences.Key.forgejoServers)
        XCTAssertNil(StandalonePreferences.offer(standalone: standalone, module: module), "The module store is not empty")
    }

    func testImportingWritesOnlyTheModuleStoreAndIsNotOfferedAgain() throws {
        let standalone = scratch("standalone"), module = scratch("module")
        standalone.set(["/Users/example/runners/a"], forKey: StandalonePreferences.Key.runnerDirectories)
        standalone.set(["https://forge.example.com", "https://forge.example.org"], forKey: StandalonePreferences.Key.forgejoServers)
        let before = snapshot(standalone)

        let offer = try XCTUnwrap(StandalonePreferences.offer(standalone: standalone, module: module))
        offer.apply(to: module)

        XCTAssertEqual(module.stringArray(forKey: StandalonePreferences.Key.runnerDirectories), ["/Users/example/runners/a"])
        XCTAssertEqual(module.stringArray(forKey: StandalonePreferences.Key.forgejoServers),
                       ["https://forge.example.com", "https://forge.example.org"])
        XCTAssertEqual(module.string(forKey: StandalonePreferences.Key.defaultForgejoServer), "https://forge.example.com")
        XCTAssertEqual(module.string(forKey: StandalonePreferences.decisionKey), "imported")
        XCTAssertEqual(snapshot(standalone), before, "The standalone domain is never written")
        XCTAssertNil(StandalonePreferences.offer(standalone: standalone, module: module))
    }

    func testDecliningIsRememberedAndChangesNothingElse() {
        let standalone = scratch("standalone"), module = scratch("module")
        standalone.set(["/Users/example/runners/a"], forKey: StandalonePreferences.Key.runnerDirectories)
        let before = snapshot(standalone)

        StandalonePreferences.decline(in: module)

        XCTAssertNil(StandalonePreferences.offer(standalone: standalone, module: module))
        XCTAssertNil(module.stringArray(forKey: StandalonePreferences.Key.runnerDirectories))
        XCTAssertEqual(snapshot(standalone), before)
    }

    // MARK: - Fixtures

    private func scratch(_ role: String) -> UserDefaults {
        let name = "RunningManCoreTests.\(role).\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    private func snapshot(_ defaults: UserDefaults) -> [String: String] {
        let keys = [StandalonePreferences.Key.runnerDirectories, StandalonePreferences.Key.forgejoServers,
                    StandalonePreferences.Key.defaultForgejoServer, StandalonePreferences.decisionKey]
        return Dictionary(uniqueKeysWithValues: keys.map { ($0, String(describing: defaults.object(forKey: $0))) })
    }
}
