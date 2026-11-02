import XCTest
@testable import MurtenCore

final class SuggestionStoreTests: XCTestCase {
    private let rule = ReclaimableRule()

    func testRecordPersistsAndRestoresAcrossInstances() async {
        let persistence = MemoryPersistence()
        let store = SuggestionStore(persistence: persistence, knownModules: [dockvac])
        await store.record(complete([reclaimable(8 * gigabyte)]), rule: rule, at: t0)
        await store.snooze(reclaimable(0).key, until: at(3600))

        let restored = SuggestionStore(persistence: persistence, knownModules: [dockvac])
        let outcome = await restored.load(at: at(60))

        XCTAssertEqual(outcome, .restored(records: 1))
        let hidden = await restored.suggestions(at: at(60))
        XCTAssertTrue(hidden.isEmpty, "the snooze survives a restart")
        let shown = await restored.suggestions(at: at(3600))
        XCTAssertEqual(shown.count, 1)
    }

    func testRestoringNeverReplaysNotifications() async {
        let persistence = MemoryPersistence()
        let store = SuggestionStore(persistence: persistence, knownModules: [dockvac])
        let events = await store.record(complete([reclaimable(8 * gigabyte)]), rule: rule, at: t0)
        let first = await store.claimNotifications(for: events, notifying: [dockvac], at: t0)
        XCTAssertEqual(first.count, 1)

        let restored = SuggestionStore(persistence: persistence, knownModules: [dockvac])
        _ = await restored.load(at: at(60))
        let refresh = await restored.record(complete([reclaimable(9 * gigabyte, at: at(60))], at: at(60)), rule: rule, at: at(60))
        let again = await restored.claimNotifications(for: refresh, notifying: [dockvac], at: at(60))
        XCTAssertTrue(again.isEmpty)
    }

    func testNotificationsRequireOptIn() async {
        let store = SuggestionStore(persistence: MemoryPersistence(), knownModules: [dockvac])
        let events = await store.record(complete([reclaimable(8 * gigabyte)]), rule: rule, at: t0)
        let claimed = await store.claimNotifications(for: events, notifying: [], at: t0)
        XCTAssertTrue(claimed.isEmpty)
    }

    func testUnknownModuleObservationIsDropped() async {
        let store = SuggestionStore(persistence: MemoryPersistence(), knownModules: ["repomen"])
        let events = await store.record(complete([reclaimable(8 * gigabyte)]), rule: rule, at: t0)
        XCTAssertEqual(events, [])
    }

    func testUnreadableFileIsQuarantinedNotOverwrittenSilently() async {
        struct Corrupt: Error {}
        let persistence = MemoryPersistence(failure: Corrupt())
        let store = SuggestionStore(persistence: persistence, knownModules: [dockvac])
        let outcome = await store.load(at: t0)

        guard case .recovered = outcome else { return XCTFail("expected recovery, got \(outcome)") }
        XCTAssertTrue(persistence.quarantined)
    }

    func testFailedQuarantineNeverOverwritesTheUnreadableFile() async {
        struct Corrupt: Error {}
        struct MoveFailed: Error {}
        let persistence = MemoryPersistence(failure: Corrupt(), quarantineFailure: MoveFailed())
        let store = SuggestionStore(persistence: persistence, knownModules: [dockvac])
        _ = await store.load(at: t0)
        await store.record(complete([reclaimable(8 * gigabyte)]), rule: ReclaimableRule(), at: t0)

        XCTAssertEqual(persistence.saveCount, 0, "the unreadable file stays as it was")
        let error = await store.persistenceError
        XCTAssertNotNil(error, "the user is told suggestions are not being saved")
        let shown = await store.suggestions(at: t0)
        XCTAssertEqual(shown.count, 1, "the store keeps working in memory")
    }

    func testQuarantineNamesNeverCollide() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = JSONFileSuggestionPersistence(fileURL: directory.appendingPathComponent("suggestions.json"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try Data("bad".utf8).write(to: persistence.fileURL)
        let first = try XCTUnwrap(try persistence.quarantine())
        try Data("bad again".utf8).write(to: persistence.fileURL)
        let second = try XCTUnwrap(try persistence.quarantine())
        XCTAssertNotEqual(first, second)
    }

    func testChangesStreamYieldsOnRecord() async {
        let store = SuggestionStore(persistence: MemoryPersistence(), knownModules: [dockvac])
        let changes = await store.changes()
        await store.record(complete([reclaimable(8 * gigabyte)]), rule: rule, at: t0)

        var iterator = changes.makeAsyncIterator()
        let next: Void? = await iterator.next()
        XCTAssertNotNil(next)
    }

    // MARK: - File persistence

    func testJSONFileRoundTripAndQuarantine() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = JSONFileSuggestionPersistence(fileURL: directory.appendingPathComponent("suggestions.json"))

        XCTAssertNil(try persistence.load())

        var ledger = SuggestionLedger()
        ledger.apply(complete([reclaimable(8 * gigabyte)]), rule: rule)
        try persistence.save(ledger)
        XCTAssertEqual(try persistence.load(), ledger)

        try Data("{not json".utf8).write(to: persistence.fileURL)
        XCTAssertThrowsError(try persistence.load())
        let moved = try XCTUnwrap(try persistence.quarantine())
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: persistence.fileURL.path))
    }

    func testJSONFileRejectsUnknownVersion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("suggestions.json")
        try Data(#"{"version": 99, "ledger": {"records": []}}"#.utf8).write(to: url)

        XCTAssertThrowsError(try JSONFileSuggestionPersistence(fileURL: url).load()) { error in
            XCTAssertEqual(error as? JSONFileSuggestionPersistence.FormatError, .unsupportedVersion(99))
        }
    }
}
