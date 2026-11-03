import XCTest
import ShortkingCore
import ShortkingKit
@testable import ShortkingModule

/// The module's state against temporary files and throwaway defaults, never the
/// user's own Application Support folder.
final class ShortkingStoreTests: XCTestCase {

    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShortkingStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "ShortkingStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    private func contents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    // MARK: - The watcher's file reader

    func testReaderUnderstandsWhatJSONStoreWrites() throws {
        XCTAssertEqual(StoreFileReader.supportedSchemaVersion, JSONStore<[Claim]>.currentSchemaVersion)

        let file = directory.appendingPathComponent(ClaimDatabase.filename)
        let claim = Claim(combo: KeyCombo(keyCode: 0x31, modifiers: [.command]), layer: .windowServer,
                          status: .known, owner: Owner(name: "Raycast", bundleID: "com.raycast.macos"))
        XCTAssertTrue(JSONStore<[Claim]>(url: file).save([claim]))

        let inventory = LiveShortcutInventory(inventoryFile: file,
                                              acknowledgements: ConflictAcknowledgements(defaults: defaults))
        let read = try XCTUnwrap(try inventory.savedInventory())
        XCTAssertEqual(read.map(\.identity), [claim.identity])
    }

    func testMissingInventoryIsNil() throws {
        let inventory = LiveShortcutInventory(inventoryFile: directory.appendingPathComponent("claims.json"),
                                              acknowledgements: ConflictAcknowledgements(defaults: defaults))
        XCTAssertNil(try inventory.savedInventory())
        XCTAssertEqual(try contents(), [], "looking creates nothing")
    }

    func testUnreadableInventoryIsLeftAlone() throws {
        let file = directory.appendingPathComponent("claims.json")
        try Data("{ not json".utf8).write(to: file)
        let inventory = LiveShortcutInventory(inventoryFile: file,
                                              acknowledgements: ConflictAcknowledgements(defaults: defaults))

        XCTAssertThrowsError(try inventory.savedInventory()) { error in
            XCTAssertEqual(error as? StoreFileReader.ReadError, .malformed)
        }
        XCTAssertEqual(try contents(), ["claims.json"], "no quarantine copy, no move")
        XCTAssertEqual(try Data(contentsOf: file), Data("{ not json".utf8))
    }

    // MARK: - Acknowledgements

    func testAcknowledgementsRoundTrip() {
        let store = ConflictAcknowledgements(defaults: defaults)
        store.acknowledge("k49|m1#a,b")
        store.acknowledge("k5|m3#c,d")
        store.acknowledge("k49|m1#a,b")

        XCTAssertEqual(store.signatures, ["k49|m1#a,b", "k5|m3#c,d"])
        XCTAssertEqual(LiveShortcutInventory(inventoryFile: directory, acknowledgements: store)
            .acknowledgedConflicts(), store.signatures)

        store.withdraw("k49|m1#a,b")
        XCTAssertEqual(store.signatures, ["k5|m3#c,d"])
    }

    func testAcknowledgementsAreBounded() {
        let store = ConflictAcknowledgements(defaults: defaults)
        for index in 0...ConflictAcknowledgements.limit {
            store.acknowledge("signature-\(index)")
        }

        XCTAssertEqual(store.signatures.count, ConflictAcknowledgements.limit)
        XCTAssertFalse(store.contains("signature-0"), "the oldest goes first")
        XCTAssertTrue(store.contains("signature-\(ConflictAcknowledgements.limit)"))
    }

    // MARK: - Settings

    @MainActor
    func testImportsTheStandaloneSettingsOnceWithoutTouchingThem() throws {
        let legacy = directory.appendingPathComponent(SettingsStore.filename)
        var standalone = AppSettings()
        standalone.scanOptions.probeBreadth = .exhaustive
        standalone.differentialLearningEnabled = false
        standalone.hasCompletedOnboarding = true
        XCTAssertTrue(JSONStore<AppSettings>(url: legacy).save(standalone))
        let original = try Data(contentsOf: legacy)

        let store = ShortkingSettingsStore(defaults: defaults, legacyFile: legacy)

        XCTAssertEqual(store.current.scanOptions.probeBreadth, .exhaustive)
        XCTAssertFalse(store.current.differentialLearningEnabled)
        XCTAssertFalse(store.current.hasCompletedOnboarding,
                       "grants belong to Murten Utilities, so its onboarding runs again")
        XCTAssertEqual(try Data(contentsOf: legacy), original, "the standalone app's file is never written")
        XCTAssertNotNil(defaults.data(forKey: ShortkingSettingsStore.key))
    }

    @MainActor
    func testStoredSettingsWinOverTheStandaloneFile() throws {
        let legacy = directory.appendingPathComponent(SettingsStore.filename)
        var standalone = AppSettings()
        standalone.scanOptions.probeBreadth = .exhaustive
        XCTAssertTrue(JSONStore<AppSettings>(url: legacy).save(standalone))

        let first = ShortkingSettingsStore(defaults: defaults, legacyFile: nil)
        first.update { $0.scanOptions.probeBreadth = .wide }

        let second = ShortkingSettingsStore(defaults: defaults, legacyFile: legacy)
        XCTAssertEqual(second.current.scanOptions.probeBreadth, .wide)
    }

    @MainActor
    func testStartsFromDefaultsWithoutAStandaloneFile() {
        let store = ShortkingSettingsStore(defaults: defaults,
                                           legacyFile: directory.appendingPathComponent("settings.json"))
        XCTAssertEqual(store.current, AppSettings())
    }

    @MainActor
    func testUnreadableStandaloneSettingsAreLeftAlone() throws {
        let legacy = directory.appendingPathComponent(SettingsStore.filename)
        try Data("garbage".utf8).write(to: legacy)

        let store = ShortkingSettingsStore(defaults: defaults, legacyFile: legacy)

        XCTAssertEqual(store.current, AppSettings())
        XCTAssertEqual(try contents(), [SettingsStore.filename], "no quarantine copy")
    }
}
