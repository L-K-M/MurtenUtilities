import XCTest
@testable import ShortkingCore

/// Reading Shortking's store files without the repair `JSONStore.load()` does.
final class StoreFileReaderTests: XCTestCase {

    /// A `claims.json` as the standalone app writes it.
    private let claimsFile = """
    {
      "payload" : [
        {
          "combo" : { "character" : "SPACE", "keyCode" : 49, "modifiers" : 3 },
          "confidence" : 1,
          "enabled" : true,
          "evidence" : [],
          "firstSeen" : "2026-10-01T08:00:00Z",
          "id" : "6F9619FF-8B86-D011-B42D-00C04FC964FF",
          "label" : "Toggle",
          "lastConfirmed" : "2026-10-30T08:00:00Z",
          "layer" : 3,
          "owner" : { "bundleID" : "com.raycast.macos", "kind" : "application", "name" : "Raycast" },
          "status" : "known"
        }
      ],
      "schemaVersion" : 1,
      "writtenAt" : "2026-10-30T08:00:01Z"
    }
    """

    func testReadsTheClaimsPayload() throws {
        let claims = try StoreFileReader.payload([Claim].self, from: Data(claimsFile.utf8))

        XCTAssertEqual(claims.count, 1)
        XCTAssertEqual(claims.first?.owner?.name, "Raycast")
        XCTAssertEqual(claims.first?.layer, .windowServer)
        XCTAssertEqual(claims.first?.combo, KeyCombo(keyCode: 0x31, modifiers: [.command, .shift]))
    }

    func testANewerFileIsReportedAsNewer() {
        let newer = claimsFile.replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 2")
        XCTAssertThrowsError(try StoreFileReader.payload([Claim].self, from: Data(newer.utf8))) { error in
            XCTAssertEqual(error as? StoreFileReader.ReadError, .newerSchema(2))
        }
    }

    func testGarbageIsMalformed() {
        XCTAssertThrowsError(try StoreFileReader.payload([Claim].self, from: Data("not json".utf8))) { error in
            XCTAssertEqual(error as? StoreFileReader.ReadError, .malformed)
        }
    }

    func testAPayloadOfAnotherShapeIsMalformed() {
        let other = #"{"schemaVersion": 1, "writtenAt": "2026-10-30T08:00:01Z", "payload": {"x": 1}}"#
        XCTAssertThrowsError(try StoreFileReader.payload([Claim].self, from: Data(other.utf8))) { error in
            XCTAssertEqual(error as? StoreFileReader.ReadError, .malformed)
        }
    }
}
