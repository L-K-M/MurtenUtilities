import XCTest
@testable import ObtainintoshCore

final class FontVersionReaderTests: XCTestCase {
    /// Runs the reader over in-memory bytes, recording the reads it asks for.
    private func readVersion(_ font: [UInt8]) -> (Result<String, Error>, [Range<UInt64>]) {
        var reader = FontVersionReader()
        var step = reader.start()
        var reads: [Range<UInt64>] = []
        while true {
            switch step {
            case .version(let version):
                return (.success(version), reads)
            case .read(let range):
                reads.append(range)
                let end = min(Int(range.upperBound), font.count)
                let start = min(Int(range.lowerBound), end)
                do {
                    step = try reader.advance(Array(font[start..<end]))
                } catch {
                    return (.failure(error), reads)
                }
            }
        }
    }

    func testReadsTheDeclaredVersionInTwoReads() throws {
        let (version, reads) = readVersion(TestFonts.font([(TestFonts.windowsPlatform, "Version 1.107")]))
        XCTAssertEqual(try version.get(), "1.107")
        XCTAssertEqual(reads.count, 2)
        XCTAssertEqual(reads[0], 0..<FontVersionReader.headerLength)
    }

    func testReadsCFFAndAppleTrueTypeFonts() throws {
        for sfnt in [Array("OTTO".utf8), Array("true".utf8)] {
            let font = TestFonts.sfnt(at: 0, version: sfnt, versions: [(TestFonts.windowsPlatform, "Version 2.0")],
                                      revision: 0)
            XCTAssertEqual(try readVersion(font).0.get(), "2.0")
        }
    }

    func testReadsTheFirstFontOfACollection() throws {
        let directoryOffset = 16
        var collection: [UInt8] = Array("ttcf".utf8) + [0, 1, 0, 0, 0, 0, 0, 1]
        collection += TestFonts.be32(UInt32(directoryOffset))
        collection += TestFonts.sfnt(at: directoryOffset, version: [0, 1, 0, 0],
                                     versions: [(TestFonts.windowsPlatform, "Version 3.1")], revision: 0)

        let (version, reads) = readVersion(collection)

        XCTAssertEqual(try version.get(), "3.1")
        XCTAssertEqual(reads.count, 3)
        XCTAssertEqual(reads[1].lowerBound, UInt64(directoryOffset))
    }

    func testPrefersUnicodeStringsAndFallsBackToMacintoshOnes() throws {
        let font = TestFonts.font([
            (TestFonts.macintoshPlatform, "Version 1.0"),
            (TestFonts.unicodePlatform, "Version 1.1"),
            (TestFonts.windowsPlatform, "Version 1.2"),
        ])
        XCTAssertEqual(try readVersion(font).0.get(), "1.2")

        XCTAssertEqual(try readVersion(TestFonts.font([(TestFonts.macintoshPlatform, "Version 1.0")])).0.get(), "1.0")
    }

    func testVersionStringsLoseTheirPrefixAndBuildNotes() {
        let cases: [(String, String?)] = [
            ("Version 1.107", "1.107"),
            ("Version: 1.2", "1.2"),
            ("Version 2.304; ttfautohint (v1.8.4.7-5d5b)", "2.304"),
            ("Version 4.001;git-0a5106e0b", "4.001"),
            ("version 1.00 December 1, 2020", "1.00"),
            ("4.001", "4.001"),
            ("v1.2.", "1.2"),
            ("Version Beta", nil),
            ("", nil),
        ]
        for (text, expected) in cases {
            XCTAssertEqual(FontVersionReader.versionNumber(text), expected, text)
        }
    }

    func testRejectsFilesThatAreNotFonts() {
        for bytes in [Array("version https://git-lfs.github.com/spec/v1\n".utf8), Array("<!DOCTYPE html>".utf8),
                      Array("wOF2".utf8) + [0, 1, 0, 0], []] {
            guard case .failure(let error) = readVersion(bytes).0 else { return XCTFail("read a non-font") }
            XCTAssertEqual("\(error)", "Not a font file")
        }
    }

    func testAVersionStringWithoutANumberFallsBackToTheRevision() throws {
        // 1.107 as font tools store it: 72548 / 65536 = 1.10699…
        for (revision, expected) in [(Int32(72548), "1.107"), (65536, "1.000")] {
            let font = TestFonts.sfnt(at: 0, version: Array("OTTO".utf8),
                                      versions: [(TestFonts.windowsPlatform, "Version  ")], revision: revision)
            let (version, reads) = readVersion(font)
            XCTAssertEqual(try version.get(), expected)
            XCTAssertEqual(reads.count, 3)
        }
    }

    func testAnEmptyNameTableFallsBackToTheRevision() throws {
        var font = TestFonts.sfnt(at: 0, version: Array("OTTO".utf8),
                                  versions: [(TestFonts.windowsPlatform, "Version 1.0")], revision: 65536)
        font.replaceSubrange(TestFonts.nameLengthOffset..<TestFonts.nameLengthOffset + 4, with: [0, 0, 0, 0])

        let (version, reads) = readVersion(font)

        XCTAssertEqual(try version.get(), "1.000")
        XCTAssertEqual(reads.count, 2)
    }

    func testADirectoryLongerThanTheFirstReadKeepsTheTablesFound() throws {
        var font = TestFonts.font([(TestFonts.windowsPlatform, "Version 1.2")])
        // More tables than the first read could ever hold.
        font.replaceSubrange(4..<6, with: TestFonts.be16(300))
        XCTAssertEqual(try readVersion(font).0.get(), "1.2")
    }

    func testAFontWithoutAVersionIsAnError() {
        guard case .failure(let error) = readVersion(TestFonts.font([(TestFonts.windowsPlatform,
                                                                       "Release candidate")])).0 else {
            return XCTFail("found a version")
        }
        XCTAssertEqual("\(error)", "The font declares no version")
    }

    func testRecognisesInstallableFontFiles() {
        XCTAssertTrue(FontFile.isFontFile("C64Keyboard-Regular.ttf"))
        XCTAssertTrue(FontFile.isFontFile("fonts/Inter.OTF"))
        XCTAssertTrue(FontFile.isFontFile("Sarasa.ttc"))
        XCTAssertFalse(FontFile.isFontFile("Inter.woff2"))
        XCTAssertFalse(FontFile.isFontFile("ttf.zip"))
    }
}
