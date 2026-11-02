import XCTest
@testable import RepoMenCore

/// Sizing against a synthetic tree — in particular the hardlink dedup, which keeps
/// pnpm-style link farms from being counted once per link.
final class DirectorySizerTests: XCTestCase {

    private var root: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RepoMenDirectorySizerTests-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
    }

    private func patternData(_ count: Int) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0) })
    }

    func testMeasuresRegularFilesAndCompletes() throws {
        try patternData(10_000).write(to: root.appendingPathComponent("a.bin"))
        let measurement = DirectorySizer.measure(root)
        XCTAssertTrue(measurement.isComplete)
        XCTAssertGreaterThanOrEqual(measurement.bytes, 10_000)
    }

    func testHardlinkedFilesCountOnce() throws {
        let original = root.appendingPathComponent("original.bin")
        try patternData(100_000).write(to: original)
        try fileManager.linkItem(at: original, to: root.appendingPathComponent("link1.bin"))
        try fileManager.linkItem(at: original, to: root.appendingPathComponent("link2.bin"))

        let measurement = DirectorySizer.measure(root)
        XCTAssertGreaterThanOrEqual(measurement.bytes, 100_000)
        XCTAssertLessThan(measurement.bytes, 200_000,
                          "three directory entries share one inode — count it once")
    }

    func testNewestModificationTracked() throws {
        let url = root.appendingPathComponent("pinned.txt")
        try patternData(1).write(to: url)
        let pinned = Date().addingTimeInterval(-3_600)
        try fileManager.setAttributes([.modificationDate: pinned], ofItemAtPath: url.path)
        // Writing the file touched the folder; the sizer counts the folder's
        // own mtime too, so pin it as well.
        try fileManager.setAttributes([.modificationDate: pinned], ofItemAtPath: root.path)
        let measurement = DirectorySizer.measure(root)
        XCTAssertEqual(measurement.newestModification.timeIntervalSince1970,
                       pinned.timeIntervalSince1970, accuracy: 1.0,
                       "newestModification should mirror the newest file mtime")
    }

    func testFutureRootModificationDoesNotWin() throws {
        let url = root.appendingPathComponent("real.txt")
        try patternData(1).write(to: url)
        let real = Date().addingTimeInterval(-3_600)
        try fileManager.setAttributes([.modificationDate: real], ofItemAtPath: url.path)
        // A skewed or hand-set future mtime on the root must not poison the result.
        try fileManager.setAttributes([.modificationDate: Date().addingTimeInterval(86_400)],
                                      ofItemAtPath: root.path)

        let measurement = DirectorySizer.measure(root)
        XCTAssertLessThanOrEqual(measurement.newestModification, Date(),
                                 "newestModification must never report a future date")
        XCTAssertEqual(measurement.newestModification.timeIntervalSince1970,
                       real.timeIntervalSince1970, accuracy: 1.0)
    }
}
