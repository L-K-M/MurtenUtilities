import XCTest
@testable import ObtainintoshCore

/// The table's "Update Available" logic. node-semver had no tests in the
/// standalone app; these pin the behaviour its calls had.
final class VersionComparisonTests: XCTestCase {
    func testStrictSemanticVersions() {
        XCTAssertNotNil(SemanticVersion(strict: "1.2.3"))
        XCTAssertNotNil(SemanticVersion(strict: "v1.2.3"))
        XCTAssertNotNil(SemanticVersion(strict: "1.2.3-beta.1+build.7"))
        XCTAssertNil(SemanticVersion(strict: "1.2"))
        XCTAssertNil(SemanticVersion(strict: "01.2.3"))
        XCTAssertNil(SemanticVersion(strict: "1.2.3-01"))
        XCTAssertNil(SemanticVersion(strict: "1.2.3-"))
        XCTAssertNil(SemanticVersion(strict: "1.2.3.4"))
        XCTAssertNil(SemanticVersion(strict: "99999999999999999.0.0"))
    }

    func testPrecedenceFollowsSemver() throws {
        let ordered = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2",
                       "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.0.1", "1.10.0"]
        let versions = try ordered.map { try XCTUnwrap(SemanticVersion(strict: $0)) }
        for (lower, higher) in zip(versions, versions.dropFirst()) {
            XCTAssertLessThan(lower, higher)
        }
        XCTAssertEqual(SemanticVersion(strict: "1.0.0+a"), SemanticVersion(strict: "1.0.0+b"))
    }

    func testCoerceFindsTheFirstVersionInText() {
        XCTAssertEqual(SemanticVersion.coerce("Version 2.4 beta"), SemanticVersion(strict: "2.4.0"))
        XCTAssertEqual(SemanticVersion.coerce("1.2.3.4"), SemanticVersion(strict: "1.2.3"))
        XCTAssertEqual(SemanticVersion.coerce("r2024-01"), SemanticVersion(strict: "2024.0.0"))
        XCTAssertNil(SemanticVersion.coerce("nightly"))
        // node-semver re-parses strictly, so a leading zero yields nothing.
        XCTAssertNil(SemanticVersion.coerce("01.2"))
    }

    func testHasUpdate() {
        let cases: [(String?, String?, Bool)] = [
            ("1.9.0", "1.10.0", true),
            ("1.0.0", "1.0.0", false),
            ("2.0.0", "1.9.9", false),
            ("v1.2.3", "1.2.4", true),
            // Coerced: four components and short versions.
            ("1.2", "1.3", true),
            ("1.2.3.4", "1.2.3.5", false),
            // A prerelease of the installed version is older.
            ("1.0.0", "1.0.0-beta.1", false),
            ("1.0.0-beta.1", "1.0.0", true),
            // Text without numbers falls back to a numeric-aware comparison.
            ("build-b", "build-c", true),
            // Unknown on either side means no update.
            (nil, "1.0.0", false),
            ("1.0.0", nil, false),
            ("", "1.0.0", false),
        ]
        for (current, latest, expected) in cases {
            XCTAssertEqual(VersionComparison.hasUpdate(current: current, latest: latest), expected,
                           "\(current ?? "nil") → \(latest ?? "nil")")
        }
    }

    func testSortingPutsUnknownVersionsFirst() {
        XCTAssertEqual(VersionComparison.compareForSorting(nil, "1.0"), .orderedAscending)
        XCTAssertEqual(VersionComparison.compareForSorting("1.0", nil), .orderedDescending)
        XCTAssertEqual(VersionComparison.compareForSorting(nil, ""), .orderedSame)
        XCTAssertEqual(VersionComparison.compareForSorting("1.9", "1.10"), .orderedAscending)
    }
}
