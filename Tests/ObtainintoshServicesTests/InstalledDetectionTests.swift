import XCTest
import ObtainintoshCore
@testable import ObtainintoshServices

/// Installed-version detection against fixture bundles and fonts in scratch
/// folders, never the real /Applications or font folders.
final class InstalledDetectionTests: XCTestCase {
    // MARK: - Programs

    func testIndexedMatchesPreserveFolderAndExactMatchPrecedence() {
        let folder = InstalledAppIndex.index(URL(fileURLWithPath: "/Applications"), entries: [
            URL(fileURLWithPath: "/Applications/Thing.app"), URL(fileURLWithPath: "/Applications/Notes.txt"),
            URL(fileURLWithPath: "/Applications/Other.app"),
        ])
        let candidates = InstalledAppIndex(folders: [folder]).candidates(for: "Thing").map(\.path)

        // The exact-cased path is tried first, so which bundle wins cannot change.
        XCTAssertEqual(candidates.first, "/Applications/Thing.app")
        // Non-.app entries are never indexed.
        XCTAssertFalse(candidates.contains { $0.hasSuffix("Notes.txt") })
    }

    func testIndexedMatchesAreCaseInsensitiveButNameSpecific() {
        let folder = InstalledAppIndex.index(URL(fileURLWithPath: "/Applications"), entries: [
            URL(fileURLWithPath: "/Applications/ThInG.app"), URL(fileURLWithPath: "/Applications/Thingamajig.app"),
        ])
        let candidates = InstalledAppIndex(folders: [folder]).candidates(for: "thing").map(\.path)

        XCTAssertTrue(candidates.contains("/Applications/ThInG.app"))
        // A longer name that merely starts the same is not a match.
        XCTAssertFalse(candidates.contains("/Applications/Thingamajig.app"))
    }

    func testFindsABundleByNameAndReadsItsVersion() {
        let system = ScratchDirectory("apps-system")
        let user = ScratchDirectory("apps-user")
        user.bundle("Tool.app", ["CFBundleShortVersionString": "2.0", "CFBundleIdentifier": "com.example.tool"])
        system.bundle("tool.app", ["CFBundleVersion": "17"])

        let index = InstalledAppIndex.scan(folders: [system.url, user.url])

        // The first folder's case-insensitive match wins over the second's exact one.
        XCTAssertEqual(index.detect(name: "Tool", bundleID: nil)?.version, "17")
        XCTAssertNil(index.detect(name: "Missing", bundleID: nil))
    }

    func testABundleWithoutAVersionIsSkipped() {
        let folder = ScratchDirectory("apps-broken")
        folder.bundle("Broken.app", ["CFBundleName": "Broken"])
        XCTAssertNil(InstalledAppIndex.scan(folders: [folder.url]).detect(name: "Broken", bundleID: nil))
    }

    func testARecordedBundleIdentifierIsPreferredOverTheName() {
        let folder = ScratchDirectory("apps-bundle-id")
        folder.bundle("Tool.app", ["CFBundleShortVersionString": "1.0", "CFBundleIdentifier": "com.example.other"])
        let renamed = folder.bundle("Tool Pro.app", ["CFBundleShortVersionString": "3.1",
                                                     "CFBundleIdentifier": "com.example.tool"])

        let index = InstalledAppIndex.scan(folders: [folder.url])

        let found = index.detect(name: "Tool", bundleID: "com.example.tool")
        XCTAssertEqual(found?.version, "3.1")
        XCTAssertEqual(found.map { URL(fileURLWithPath: $0.path).lastPathComponent }, renamed.lastPathComponent)
        // Without a match for the identifier, the name still finds the program.
        XCTAssertEqual(index.detect(name: "Tool", bundleID: "com.example.missing")?.version, "1.0")
    }

    // MARK: - Fonts

    func testFindsAnInstalledFontByFileNameInAnyFormat() {
        let fonts = ScratchDirectory("fonts-formats")
        let installed = fonts.write(TestFonts.font(declaring: "1.107"), to: "c64keyboard-regular.OTF")
        fonts.write(TestFonts.font(declaring: "9.0"), to: "Other-Regular.ttf")

        let index = InstalledFontIndex.scan(folders: [fonts.url])

        let found = index.detect(fontFileName: "C64Keyboard-Regular.ttf")
        XCTAssertEqual(found?.version, "1.107")
        XCTAssertEqual(found.map { URL(fileURLWithPath: $0.path).lastPathComponent }, installed.lastPathComponent)
        XCTAssertNil(index.detect(fontFileName: "Missing-Regular.ttf"))
        XCTAssertNil(index.detect(fontFileName: "C64Keyboard-Regular.zip"))
    }

    func testTheNewestCopyWins() {
        let user = ScratchDirectory("fonts-user")
        let system = ScratchDirectory("fonts-system")
        user.write(TestFonts.font(declaring: "3.9"), to: "Inter.ttf")
        let newer = system.write(TestFonts.font(declaring: "3.10"), to: "truetype/inter/Inter.ttf")

        let index = InstalledFontIndex.scan(folders: [user.url, system.url])

        let found = index.detect(fontFileName: "Inter.ttf")
        XCTAssertEqual(found?.version, "3.10")
        XCTAssertTrue(found?.path.hasSuffix("truetype/inter/Inter.ttf") == true, found?.path ?? "nil")
        XCTAssertEqual(newer.lastPathComponent, "Inter.ttf")
    }

    func testUnreadableCopiesAreSkipped() {
        let fonts = ScratchDirectory("fonts-unreadable")
        fonts.write(Array("not a font".utf8), to: "Broken.ttf")
        XCTAssertNil(InstalledFontIndex.scan(folders: [fonts.url]).detect(fontFileName: "Broken.ttf"))
    }

    func testReadsTheVersionOfAFontAtAKnownPath() throws {
        let fonts = ScratchDirectory("fonts-path")
        let path = fonts.write(TestFonts.font(declaring: "2.0"), to: "Abacus.otf")

        XCTAssertEqual(InstalledFontIndex.version(at: path), "2.0")
        try FileManager.default.removeItem(at: path)
        XCTAssertNil(InstalledFontIndex.version(at: path))
    }

    func testFontLookupsFallBackToTheProgramDetection() async {
        let fonts = ScratchDirectory("fonts-lookups")
        let known = fonts.write(TestFonts.font(declaring: "1.5"), to: "Known.ttf")
        let detector = InstalledVersionDetector(applicationFolders: [], fontFolders: [fonts.url])

        let results = await detector.detectFonts([nil, .named("Known.otf"), .named("Gone.ttf"),
                                                  .lastFoundAt(known.path), .lastFoundAt("/nonexistent/Font.ttf")])

        XCTAssertEqual(results.count, 5)
        XCTAssertEqual(results[0], .notAFont)
        guard case .installed(let named) = results[1] else { return XCTFail("\(results[1])") }
        XCTAssertEqual(named.version, "1.5")
        XCTAssertEqual(results[2], .notInstalled)
        XCTAssertEqual(results[3], .installed(InstalledVersion(path: known.path, version: "1.5")))
        XCTAssertEqual(results[4], .notInstalled)
    }
}
