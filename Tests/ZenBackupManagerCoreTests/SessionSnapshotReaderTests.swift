import XCTest
@testable import ZenBackupManagerCore

/// The watcher's source against a temporary Zen folder, never the real one.
final class SessionSnapshotReaderTests: XCTestCase {
    private var root: URL!
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Restore permissions changed by a test so the folder can be removed.
        if let files = FileManager.default.enumerator(atPath: root.path) {
            for case let path as String in files {
                try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.appendingPathComponent(path).path)
            }
        }
        try FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func makeProfile(_ path: String) throws -> URL {
        let directory = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent("prefs.js"))
        return directory
    }

    private func writeINI(_ paths: [String]) throws {
        let sections = paths.enumerated().map { "[Profile\($0.offset)]\nName=\($0.element)\nPath=\($0.element)\nIsRelative=1\n" }
        try sections.joined().write(to: root.appendingPathComponent("profiles.ini"), atomically: true, encoding: .utf8)
    }

    private func snapshot(_ file: URL, daysAgo: Double) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not decoded by the reader".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: base.addingTimeInterval(-daysAgo * 86_400)], ofItemAtPath: file.path)
    }

    func testListsZensProfiles() throws {
        try makeProfile("a")
        try makeProfile("b")
        try writeINI(["a", "b", "missing"])
        let names = try SessionSnapshotReader(zenRoot: root).profiles().map(\.name)
        XCTAssertEqual(names.sorted(), ["a", "b"])
    }

    func testNoProfileListMeansNoProfiles() throws {
        XCTAssertEqual(try SessionSnapshotReader(zenRoot: root).profiles().count, 0)
    }

    func testNewestSnapshotSpansCurrentAndBackupFolders() throws {
        let directory = try makeProfile("a")
        try snapshot(directory.appendingPathComponent("zen-sessions.jsonlz4"), daysAgo: 12)
        try snapshot(directory.appendingPathComponent("zen-sessions-backup/zen-sessions-1.jsonlz4"), daysAgo: 9)
        try snapshot(directory.appendingPathComponent("sessionstore-backups/recovery.baklz4"), daysAgo: 8)
        try snapshot(directory.appendingPathComponent("sessionstore-backups/notes.txt"), daysAgo: 0)
        try snapshot(directory.appendingPathComponent("unrelated.jsonlz4"), daysAgo: 0)

        let profile = ZenProfile(name: "a", directory: directory, isDefault: true)
        XCTAssertEqual(try SessionSnapshotReader(zenRoot: root).newestSnapshot(in: profile), base.addingTimeInterval(-8 * 86_400))
    }

    func testProfileWithoutSnapshotsHasNoDate() throws {
        let profile = ZenProfile(name: "a", directory: try makeProfile("a"), isDefault: true)
        XCTAssertNil(try SessionSnapshotReader(zenRoot: root).newestSnapshot(in: profile))
    }

    func testDatesSnapshotsWithoutReadingThem() throws {
        let directory = try makeProfile("a")
        let file = directory.appendingPathComponent("zen-sessions.jsonlz4")
        try snapshot(file, daysAgo: 3)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)

        let profile = ZenProfile(name: "a", directory: directory, isDefault: true)
        XCTAssertEqual(try SessionSnapshotReader(zenRoot: root).newestSnapshot(in: profile), base.addingTimeInterval(-3 * 86_400))
    }

    func testSymlinkedBackupFolderIsAFailureNotAnAbsence() throws {
        let directory = try makeProfile("a")
        let elsewhere = root.appendingPathComponent("elsewhere")
        try snapshot(elsewhere.appendingPathComponent("zen-sessions-1.jsonlz4"), daysAgo: 1)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("zen-sessions-backup"), withDestinationURL: elsewhere)

        let profile = ZenProfile(name: "a", directory: directory, isDefault: true)
        XCTAssertThrowsError(try SessionSnapshotReader(zenRoot: root).newestSnapshot(in: profile))
    }
}
