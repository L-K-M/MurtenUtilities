import XCTest
@testable import BootCaptainKit
import BootCaptainCore

final class FileJournalTests: XCTestCase {
    private final class ConcurrencyDetectingFileManager: FileManager {
        private let stateLock = NSLock()
        private var activeCalls = 0
        private(set) var overlapped = false

        override func createDirectory(atPath path: String,
                                      withIntermediateDirectories createIntermediates: Bool,
                                      attributes: [FileAttributeKey: Any]? = nil) throws {
            stateLock.withLock {
                activeCalls += 1
                overlapped = overlapped || activeCalls > 1
            }
            Thread.sleep(forTimeInterval: 0.05)
            stateLock.withLock { activeCalls -= 1 }

            try super.createDirectory(atPath: path,
                                      withIntermediateDirectories: createIntermediates,
                                      attributes: attributes)
        }
    }

    private func tempDir() -> String {
        let dir = NSTemporaryDirectory() + "bootcaptain-journal-test-" + UUID().uuidString
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    func testPrepareThenCompleteRoundTrips() throws {
        let journal = FileJournal(directory: tempDir())
        let request = ActionRequest(operation: .moveToVault, itemID: "launchDaemon:com.foo",
                                    sourcePath: "/Library/LaunchDaemons/com.foo.plist")
        let record = try XCTUnwrap(journal.prepare(request, at: 1000))
        XCTAssertEqual(record.status, .prepared)
        XCTAssertNotNil(record.inverse)
        XCTAssertEqual(record.inverse?.operation, .restoreFromVault)

        journal.complete(record, status: .committed, at: 1001)
        let all = journal.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.status, .committed)
        XCTAssertEqual(all.first?.completedAt, 1001)
    }

    func testUnfinishedFindsPreparedAndIndeterminate() throws {
        let journal = FileJournal(directory: tempDir())
        let a = try XCTUnwrap(journal.prepare(ActionRequest(operation: .moveToVault, itemID: "a"), at: 1))
        let b = try XCTUnwrap(journal.prepare(ActionRequest(operation: .moveToVault, itemID: "b"), at: 2))
        let c = try XCTUnwrap(journal.prepare(ActionRequest(operation: .moveToVault, itemID: "c"), at: 3))
        journal.complete(a, status: .committed, at: 10)   // settled
        journal.complete(b, status: .indeterminate, at: 11) // needs reconcile
        _ = c                                                // left prepared

        let unfinished = Set(journal.unfinished().map { $0.request.itemID })
        XCTAssertEqual(unfinished, ["b", "c"])
    }

    func testAllIgnoresNonJSON() {
        let dir = tempDir()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? "not json".data(using: .utf8)!.write(to: URL(fileURLWithPath: dir + "/stray.txt"))
        let journal = FileJournal(directory: dir)
        _ = journal.prepare(ActionRequest(operation: .moveToVault, itemID: "x"), at: 1)
        XCTAssertEqual(journal.all().count, 1)
    }

    func testConcurrentWritesSerializeInjectedFileManager() {
        let manager = ConcurrencyDetectingFileManager()
        let journal = FileJournal(directory: tempDir(), fileManager: manager)

        DispatchQueue.concurrentPerform(iterations: 8) { index in
            _ = journal.prepare(
                ActionRequest(operation: .moveToVault, itemID: "item-\(index)"),
                at: Double(index))
        }

        XCTAssertFalse(manager.overlapped)
        XCTAssertEqual(journal.all().count, 8)
    }
}
