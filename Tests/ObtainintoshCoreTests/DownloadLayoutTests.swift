import XCTest
@testable import ObtainintoshCore

final class DownloadLayoutTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/tmp/cache", isDirectory: true)

    func testPathsAreScopedToTheAppAndVersion() throws {
        let layout = try DownloadLayout(root: root, appKey: "app-1", version: "1.2.0", fileName: "App.dmg")
        XCTAssertEqual(layout.directory.path, "/tmp/cache/app-1/1.2.0")
        XCTAssertEqual(layout.completed.path, "/tmp/cache/app-1/1.2.0/App.dmg")
        XCTAssertEqual(layout.partial.path, "/tmp/cache/app-1/1.2.0/App.dmg.part")
    }

    func testTheSameAppAndVersionAlwaysShareADirectory() throws {
        // The deterministic location makes "already downloaded" an existence check.
        let first = try DownloadLayout(root: root, appKey: "app-1", version: "1.2.0", fileName: "App.dmg")
        let second = try DownloadLayout(root: root, appKey: "app-1", version: "1.2.0", fileName: "App.dmg")
        XCTAssertEqual(first, second)

        let otherVersion = try DownloadLayout(root: root, appKey: "app-1", version: "1.3.0", fileName: "App.dmg")
        let otherApp = try DownloadLayout(root: root, appKey: "app-2", version: "1.2.0", fileName: "App.dmg")
        XCTAssertNotEqual(first.directory, otherVersion.directory)
        XCTAssertNotEqual(first.directory, otherApp.directory)
    }

    func testUnsafeVersionAndAppComponentsCannotEscapeTheCache() throws {
        let layout = try DownloadLayout(root: root, appKey: "../../etc", version: "1.0/../../evil",
                                        fileName: "../../etc/passwd")
        XCTAssertEqual(layout.directory.path, "/tmp/cache/etc/evil")
        XCTAssertEqual(layout.completed.path, "/tmp/cache/etc/evil/passwd")

        XCTAssertEqual(DownloadLayout.safePathComponent("1.0+meta:2"), "1.0_meta_2")
        XCTAssertEqual(DownloadLayout.safePathComponent(".."), "_")
    }

    func testATraversingAssetNameStaysInsideTheDirectory() throws {
        let layout = try DownloadLayout(root: root, appKey: "app-1", version: "1.0", fileName: "../../etc/passwd")
        XCTAssertEqual(layout.completed.deletingLastPathComponent().path, layout.directory.path)
        XCTAssertThrowsError(try DownloadLayout(root: root, appKey: "app-1", version: "1.0", fileName: ".."))
    }

    func testDownloadSizeMustMatchExactly() {
        XCTAssertNoThrow(try DownloadLayout.validateSize(10, expected: 10))
        XCTAssertThrowsError(try DownloadLayout.validateSize(9, expected: 10)) {
            XCTAssertTrue("\($0)".contains("Downloaded 9 bytes"), "\($0)")
        }
        XCTAssertThrowsError(try DownloadLayout.validateSize(11, expected: 10))
    }
}
