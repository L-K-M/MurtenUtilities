import XCTest
@testable import ObtainintoshCore

final class AssetFilterTests: XCTestCase {
    private func program(_ fileName: String) -> String? {
        AssetFilter.programName(fileName)
    }

    func testHauntwareAssetsGroupIntoTheirPrograms() {
        let cases = [
            ("planchette-macos-universal.zip", "planchette"),
            ("planchette_1.9.0-1_amd64.deb", "planchette"),
            ("planchette-linux-x64.AppImage", "planchette"),
            ("planchette-linux-x64.flatpak", "planchette"),
            ("poltergeist-ios-unsigned.ipa", "poltergeist"),
            ("seance-linux-x64.tar.gz", "seance"),
            ("seance_1.9.0-1_amd64.deb", "seance"),
            ("seance-sync-linux-x64.tar.gz", "seance-sync"),
            ("seance-sync-macos-arm64.tar.gz", "seance-sync"),
        ]
        for (fileName, expected) in cases {
            XCTAssertEqual(program(fileName), expected, fileName)
        }
    }

    func testCommonReleaseToolNamingYieldsTheBareProgram() {
        let cases = [
            // Tauri bundler
            ("MyApp_1.6.0_x64.dmg", "myapp"),
            ("MyApp_1.6.0_aarch64.dmg", "myapp"),
            ("MyApp.app.tar.gz", "myapp"),
            ("my-app_1.6.0_amd64.AppImage", "my-app"),
            // electron-builder
            ("MyApp-1.2.3-arm64-mac.zip", "myapp"),
            ("MyApp-1.2.3-universal.dmg", "myapp"),
            // goreleaser
            ("tool_Darwin_arm64.tar.gz", "tool"),
            ("tool_2.1.0_linux_amd64.tar.gz", "tool"),
            // cargo-dist
            ("tool-x86_64-unknown-linux-gnu.tar.xz", "tool"),
            ("tool-aarch64-apple-darwin.tar.xz", "tool"),
            // Apple Silicon spellings and fused OS versions
            ("Tool-AppleSilicon.dmg", "tool"),
            ("tool-m1.dmg", "tool"),
            ("Tool-M5-Max.dmg", "tool"),
            ("Tool-Apple-Silicon.dmg", "tool"),
            ("tool-macos14-arm64.zip", "tool"),
            ("tool-win11-x64.zip", "tool"),
            ("tool-ubuntu2204.deb", "tool"),
            // Packaging variants of the same program
            ("Tool-Setup-1.0.pkg", "tool"),
            ("tool-portable-linux.zip", "tool"),
            // Bare archive suffixes
            ("tool.tar", "tool"),
            ("tool.tar.zst", "tool"),
            ("tool.bz2", "tool"),
        ]
        for (fileName, expected) in cases {
            XCTAssertEqual(program(fileName), expected, fileName)
        }
    }

    func testProgramWordsSurviveAndTheFirstWordAlwaysCounts() {
        let cases = [
            ("Mac-Mouse-Fix-3.0.dmg", "mac-mouse-fix"),
            ("7zip-24.08-linux-x64.tar.xz", "7zip"),
            ("0ad-0.27-linux.AppImage", "0ad"),
            ("v2ray-linux-64.zip", "v2ray"),
            ("tool-cli-linux-x64.tar.gz", "tool-cli"),
            ("tool-nightly-linux.zip", "tool-nightly"),
            ("Séance-macos.zip", "séance"),
            ("My App 1.0.dmg", "my-app"),
        ]
        for (fileName, expected) in cases {
            XCTAssertEqual(program(fileName), expected, fileName)
        }
    }

    func testEveryFontFormatIsAPackageSuffix() {
        for fileExtension in FontFile.extensions {
            XCTAssertTrue(AssetFilter.packageSuffixes.contains(fileExtension), fileExtension)
        }
    }

    func testEachFontFileIsAProgramWhateverItsFormat() throws {
        for fileName in ["C64Keyboard-Regular.ttf", "C64Keyboard-Regular.OTF"] {
            XCTAssertEqual(program(fileName), "c64keyboard-regular", fileName)
        }
        XCTAssertEqual(
            try AssetFilter.parse(
                "https://github.com/szabadkai/c64-keyboard-font/blob/main/fonts/C64Keyboard-Regular.ttf"),
            .program("c64keyboard-regular"))
    }

    func testCommitHashesEndTheProgramName() {
        XCTAssertEqual(program("tool-3f9a2c1-linux.zip"), "tool")
        XCTAssertEqual(program("tool-g3f9a2c1-linux.zip"), "tool")
        // Hex letters without a digit form a word, not a hash.
        XCTAssertEqual(program("tool-facade-linux.zip"), "tool-facade")
    }

    func testNamesWithoutAProgramHaveNone() {
        XCTAssertNil(program("1.0-linux.tar.gz"))
        XCTAssertNil(program("v2-macos.zip"))
        XCTAssertNil(program("---.zip"))
        XCTAssertNil(program(""))
    }

    func testParseReadsNamesFileNamesAndLinksAsTheSameProgram() throws {
        for input in [
            "seance",
            "  Seance ",
            "seance-macos-universal.zip",
            "seance_1.9.0-1_amd64.deb",
            "https://github.com/L-K-M/Hauntware/releases/download/v1.9.0/seance-linux-x64.AppImage?raw=1",
        ] {
            XCTAssertEqual(try AssetFilter.parse(input), .program("seance"), input)
        }
        XCTAssertEqual(try AssetFilter.parse("Seance Sync"), .program("seance-sync"))
    }

    func testParseTreatsWildcardsAsALowercasedPattern() throws {
        XCTAssertEqual(try AssetFilter.parse(" *-GTK4-*.zip "), .pattern("*-gtk4-*.zip"))
        XCTAssertEqual(try AssetFilter.parse("seance-?.zip"), .pattern("seance-?.zip"))
    }

    func testParseRefusesLinksToAnythingButAReleaseFile() {
        for link in [
            "https://github.com/L-K-M/Hauntware",
            "https://github.com/L-K-M/Hauntware/",
            "https://github.com/L-K-M/Hauntware/releases/tag/v1.9.0",
        ] {
            XCTAssertThrowsError(try AssetFilter.parse(link)) { error in
                XCTAssertTrue("\(error)".contains("not a link to a release file"), "\(error)")
            }
        }
    }

    func testParseLeavesBlankInputUnfiltered() throws {
        XCTAssertNil(try AssetFilter.parse(""))
        XCTAssertNil(try AssetFilter.parse("   "))
    }

    func testParseRefusesFiltersThatSelectNothingInParticular() {
        for input in ["*", "*.*", "?*", "1.9.0", "v2", "---"] {
            XCTAssertThrowsError(try AssetFilter.parse(input), input)
        }
    }

    func testTheCanonicalFormParsesBackToTheSameFilter() throws {
        for input in ["Seance Sync", "Mac-Mouse-Fix-3.0.dmg", "*-GTK4-*", "séance"] {
            let filter = try XCTUnwrap(try AssetFilter.parse(input))
            XCTAssertEqual(try AssetFilter.parse(filter.canonical), filter, input)
            XCTAssertEqual(try AssetFilter.canonicalize(input), filter.canonical, input)
        }
        XCTAssertNil(try AssetFilter.canonicalize(" "))
    }

    func testAProgramFilterMatchesItsOwnAssetsOnly() throws {
        let seance = try XCTUnwrap(try AssetFilter.parse("seance"))
        XCTAssertTrue(seance.matches("seance-macos-universal.zip"))
        XCTAssertTrue(seance.matches("Seance_1.9.0-1_amd64.deb"))
        XCTAssertFalse(seance.matches("seance-sync-linux-x64.tar.gz"))
        XCTAssertFalse(seance.matches("planchette-macos-universal.zip"))

        let sync = try XCTUnwrap(try AssetFilter.parse("seance-sync"))
        XCTAssertTrue(sync.matches("seance-sync-linux-x64.tar.gz"))
        XCTAssertFalse(sync.matches("seance-linux-x64.tar.gz"))
    }

    func testAPatternFilterMatchesWholeFileNamesCaseInsensitively() throws {
        let gtk4 = try XCTUnwrap(try AssetFilter.parse("*-gtk4-*"))
        XCTAssertTrue(gtk4.matches("Tool-1.0-Linux-GTK4-x64.AppImage"))
        XCTAssertFalse(gtk4.matches("tool-1.0-linux-gtk3-x64.AppImage"))

        let exact = try XCTUnwrap(try AssetFilter.parse("seance-?.zip"))
        XCTAssertTrue(exact.matches("seance-a.zip"))
        XCTAssertFalse(exact.matches("seance-ab.zip"))
        XCTAssertFalse(exact.matches("xseance-a.zip"))
    }

    func testWildcardMatchBacktracksAcrossStars() {
        XCTAssertTrue(AssetFilter.wildcardMatch("*", ""))
        XCTAssertTrue(AssetFilter.wildcardMatch("a*b*c", "aXbYbZc"))
        XCTAssertTrue(AssetFilter.wildcardMatch("*.tar.gz", "x.tar.gz.tar.gz"))
        XCTAssertTrue(AssetFilter.wildcardMatch("a?c*", "abcdef"))
        XCTAssertFalse(AssetFilter.wildcardMatch("a*b", "aXbYc"))
        XCTAssertFalse(AssetFilter.wildcardMatch("abc", "abcd"))
        XCTAssertFalse(AssetFilter.wildcardMatch("", "a"))
    }
}
