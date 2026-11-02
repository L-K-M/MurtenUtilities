import XCTest
@testable import ZenBackupManager

final class SessionPreviewTests: XCTestCase {
    func testModernSelectsCurrentHistoryEntryAndMetadata() throws {
        let result = try SessionPreview.parse(Fixture.modern)
        XCTAssertEqual(result.format, .zen)
        XCTAssertEqual(result.tabs.count, 2)
        XCTAssertEqual(result.tabs[0].title, "Swift")
        XCTAssertEqual(result.tabs[0].url, "https://swift.org")
        XCTAssertEqual(result.pinnedCount, 2)
        XCTAssertEqual(result.spaces[0].name, "Work")
        XCTAssertEqual(result.folderCount, 1)
        XCTAssertEqual(result.splitCount, 1)
        XCTAssertNotNil(result.collectedAt)
    }

    func testLegacyAndDuplicateSpacesAcrossWindows() throws {
        let result = try SessionPreview.parse(Fixture.compressed("""
        {"windows":[{"tabs":[],"spaces":[{"uuid":"a","name":"A"}]},{"tabs":[],"spaces":[{"uuid":"a","name":"A"}]}]}
        """))
        XCTAssertEqual(result.format, .firefox)
        XCTAssertEqual(result.spaces.count, 1)
    }

    func testMissingAndOutOfBoundsEntryIndexes() throws {
        let result = try SessionPreview.parse(Fixture.compressed("""
        {"tabs":[{"entries":[]},{"entries":[{"url":"a"},{"url":"b"}],"index":999},{"entries":[{"url":"a"},{"url":"b"}],"index":-4}],"spaces":[]}
        """))
        XCTAssertEqual(result.tabs.map(\.url), ["about:blank", "b", "a"])
    }

    func testEmptyModernSessionIsValid() throws {
        XCTAssertEqual(try SessionPreview.parse(Fixture.compressed("{\"tabs\":[],\"spaces\":[]}")).tabs.count, 0)
    }

    func testUnrecognizedJSONAndMalformedJSONAreRejected() {
        for text in ["{}", "{", "{\"tabs\":\"bad\",\"spaces\":[]}"] {
            XCTAssertThrowsError(try SessionPreview.parse(Fixture.compressed(text)))
        }
    }

    func testBadHeaderTruncatedAndOversizedBlocksAreRejected() {
        XCTAssertThrowsError(try MozillaLZ4.decode(Data("not a session".utf8)))
        XCTAssertThrowsError(try MozillaLZ4.decode(Fixture.modern.prefix(20)))
        var oversized = Fixture.modern
        oversized.replaceSubrange(8..<12, with: [255, 255, 255, 127])
        XCTAssertThrowsError(try MozillaLZ4.decode(oversized))
        var incorrectSize = Fixture.modern
        incorrectSize.replaceSubrange(8..<12, with: [1, 0, 0, 0])
        XCTAssertThrowsError(try MozillaLZ4.decode(incorrectSize))
    }

    func testIndependentLiteralLZ4Block() throws {
        // A raw LZ4 literal block (no encoder dependency).
        let json = Data("{\"tabs\":[],\"spaces\":[]}".utf8)
        var length = UInt32(json.count).littleEndian
        let bytes = MozillaLZ4.magic + withUnsafeBytes(of: &length) { Data($0) } + Data([0xf0, UInt8(json.count - 15)]) + json
        XCTAssertEqual(try MozillaLZ4.decode(bytes), json)
    }

    func testDifferencePreservesDuplicateURLCounts() throws {
        let before = try SessionPreview.parse(Fixture.compressed("{\"tabs\":[{\"entries\":[{\"url\":\"a\"}]},{\"entries\":[{\"url\":\"a\"}]}],\"spaces\":[]}"))
        let after = try SessionPreview.parse(Fixture.compressed("{\"tabs\":[{\"entries\":[{\"url\":\"a\"}]},{\"entries\":[{\"url\":\"b\"}]}],\"spaces\":[]}"))
        XCTAssertEqual(after.difference(from: before).added, 1)
        XCTAssertEqual(after.difference(from: before).removed, 1)
    }
}
