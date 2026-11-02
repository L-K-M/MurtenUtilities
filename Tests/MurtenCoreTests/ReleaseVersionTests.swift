import XCTest
@testable import MurtenCore

final class ReleaseVersionTests: XCTestCase {
    func testParsesTagsWithAndWithoutPrefix() {
        XCTAssertEqual(ReleaseVersion("v1.2.0")?.components, [1, 2, 0])
        XCTAssertEqual(ReleaseVersion("0.1")?.components, [0, 1])
    }

    func testRejectsPreReleasesAndGarbage() {
        XCTAssertNil(ReleaseVersion("1.2.0-beta.1"))
        XCTAssertNil(ReleaseVersion("latest"))
        XCTAssertNil(ReleaseVersion("1..2"))
        XCTAssertNil(ReleaseVersion(""))
        XCTAssertNil(ReleaseVersion("+1.0"))
    }

    func testComparesNumericallyAndPadsMissingComponents() {
        XCTAssertLessThan(ReleaseVersion("1.9.0")!, ReleaseVersion("1.10.0")!)
        XCTAssertEqual(ReleaseVersion("1.2")!, ReleaseVersion("1.2.0")!)
        XCTAssertEqual(Set([ReleaseVersion("1.2")!, ReleaseVersion("1.2.0")!]).count, 1)
        XCTAssertFalse(ReleaseVersion("2.0.0")! < ReleaseVersion("1.99.99")!)
    }
}
