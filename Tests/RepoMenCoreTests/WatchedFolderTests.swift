import XCTest
@testable import RepoMenCore

/// Persisted watch entries must survive producers that leave out optional keys —
/// one missing key must not cost the whole watch list.
final class WatchedFolderTests: XCTestCase {

    func testDecodesWithDefaultsWhenOptionalKeysAreMissing() throws {
        let folder = try JSONDecoder().decode(
            WatchedFolder.self, from: Data(#"{"path":"/Users/test/dev"}"#.utf8))
        XCTAssertEqual(folder.path, "/Users/test/dev")
        XCTAssertEqual(folder.maxIdleDays, 30)
        XCTAssertTrue(folder.isEnabled)
        XCTAssertFalse(folder.autoTrashArmed)
    }

    func testRoundTripKeepsEveryField() throws {
        let folder = WatchedFolder(path: "/Users/test/dev", maxIdleDays: 7,
                                   isEnabled: false, autoTrashArmed: true)
        let decoded = try JSONDecoder().decode(WatchedFolder.self,
                                               from: JSONEncoder().encode(folder))
        XCTAssertEqual(decoded, folder)
    }
}
