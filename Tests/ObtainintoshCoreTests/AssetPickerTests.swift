import XCTest
@testable import ObtainintoshCore

/// The macOS asset picker's tests from the standalone app. Its Linux picker
/// and their tests stayed behind: the suite runs on macOS only.
final class AssetPickerTests: XCTestCase {
    private func assets(_ names: [String]) -> [ReleaseAsset] {
        names.map { ReleaseAsset(name: $0, browserDownloadURL: "url", size: 100) }
    }

    private func pick(_ names: [String], _ architecture: CPUArchitecture = .current) -> String? {
        AssetPicker.macOSAsset(assets(names), architecture: architecture)?.name
    }

    func testAssetExtensionRequiresDot() {
        // "checksums-dmg" must not be mistaken for a .dmg file.
        XCTAssertEqual(pick(["checksums-dmg", "MyApp-macos.zip"]), "MyApp-macos.zip")
    }

    func testFerriteAssetSelection() throws {
        // Reproduction case from a user: Ferrite v0.2.3 should favour the macOS
        // tar.gz over the Windows zip.
        let selected = try XCTUnwrap(pick(["ferrite-linux-x64.tar.gz", "ferrite-macos-arm64.tar.gz",
                                           "ferrite-macos-x64.tar.gz", "ferrite-windows-x64.zip"]))
        XCTAssertTrue(selected.contains("macos"))
        XCTAssertTrue(selected.hasSuffix("tar.gz"))
    }

    func testUniversalPreferred() {
        for architecture in [CPUArchitecture.arm64, .x86_64] {
            XCTAssertEqual(pick(["tool-x86_64.dmg", "tool-universal.dmg", "tool-arm64.dmg"], architecture),
                           "tool-universal.dmg")
        }
    }

    func testNativeArchitecturePreferredForEachTarget() {
        let names = ["tool-macos-x86_64.dmg", "tool-macos-arm64.dmg"]
        XCTAssertEqual(pick(names, .arm64), "tool-macos-arm64.dmg")
        XCTAssertEqual(pick(names, .x86_64), "tool-macos-x86_64.dmg")
    }

    func testTheWrapperPicksForTheRunningArchitecture() {
        let list = assets(["tool-macos-x86_64.dmg", "tool-macos-arm64.dmg", "tool-linux-x86_64.deb",
                           "tool-linux-arm64.deb"])
        XCTAssertEqual(AssetPicker.compatibleAsset(list, filter: nil)?.name,
                       AssetPicker.macOSAsset(list, architecture: .current)?.name)
    }

    func testDmgFallbackWithoutKeywords() {
        // A dmg is macOS-specific, so it may match without a keyword.
        XCTAssertEqual(pick(["MyTool-1.2.3.dmg"]), "MyTool-1.2.3.dmg")
    }

    func testGenericArchivesRequireAMacOSMarker() {
        let names = ["tool-windows-arm64.zip", "tool-linux-x86_64.tar.gz", "tool-arm64.zip", "tool-x86_64.tar.gz"]
        for architecture in [CPUArchitecture.arm64, .x86_64] {
            XCTAssertNil(pick(names, architecture))
        }
    }

    func testArchitectureCompatibilityPrecedesPackagePreference() {
        XCTAssertEqual(pick(["tool-macos-x86_64.dmg", "tool-macos-arm64.zip"], .arm64), "tool-macos-arm64.zip")
        XCTAssertEqual(pick(["tool-macos-arm64.dmg", "tool-macos-x86_64.zip"], .x86_64), "tool-macos-x86_64.zip")
    }

    func testEqualScoresUseTheAssetNameAsTiebreaker() {
        for names in [["tool-macos-x86_64-zeta.dmg", "tool-macos-x86_64-alpha.dmg"],
                      ["tool-macos-x86_64-alpha.dmg", "tool-macos-x86_64-zeta.dmg"]] {
            XCTAssertEqual(pick(names, .x86_64), "tool-macos-x86_64-alpha.dmg")
        }
    }

    func testExplicitNonMacOSMarkersAreRejected() {
        XCTAssertEqual(pick(["tool-linux-arm64.dmg", "tool-macos-arm64.zip"], .arm64), "tool-macos-arm64.zip")
        XCTAssertEqual(pick(["tool-windows-x86_64.pkg", "tool-macos-x86_64.zip"], .x86_64), "tool-macos-x86_64.zip")
    }

    func testIntelFallbackIsAppleSiliconOnly() {
        XCTAssertEqual(pick(["tool-windows-x86_64.pkg", "tool-macos-x86_64.dmg"], .arm64), "tool-macos-x86_64.dmg")
        XCTAssertNil(pick(["tool-macos-arm64.dmg"], .x86_64))
    }

    func testUnsupportedCPUAssetsAreRejected() {
        let cases: [(CPUArchitecture, String)] = [
            (.arm64, "tool-macos-armv7.dmg"), (.arm64, "tool-macos-x86_32.dmg"), (.arm64, "tool-macos-i786.dmg"),
            (.x86_64, "tool-macos-arm64.dmg"), (.x86_64, "tool-macos-x86_32.dmg"), (.x86_64, "tool-macos-i786.dmg"),
        ]
        for (architecture, name) in cases {
            XCTAssertNil(pick([name], architecture), name)
        }
    }

    func testFontsNeedNoPlatformMarkerAndRankAfterPrograms() {
        for architecture in [CPUArchitecture.arm64, .x86_64] {
            XCTAssertEqual(pick(["Inter-Regular.otf", "Inter-Regular.ttf"], architecture), "Inter-Regular.ttf")
            XCTAssertEqual(pick(["Inter-Regular.ttf", "tool.dmg", "tool.AppImage"], architecture), "tool.dmg")
        }
    }

    func testTauriReleaseAssetsAreReadableOnEveryMac() {
        // The file names Obtainintosh's own release workflow produces: each
        // Mac gets its own disk image, never a Linux package.
        let names = ["Obtainintosh_1.6.0_aarch64.dmg", "Obtainintosh_1.6.0_x64.dmg", "Obtainintosh_1.6.0_amd64.deb",
                     "Obtainintosh_1.6.0_amd64.AppImage"]
        XCTAssertEqual(pick(names, .arm64), "Obtainintosh_1.6.0_aarch64.dmg")
        XCTAssertEqual(pick(names, .x86_64), "Obtainintosh_1.6.0_x64.dmg")
    }

    func testUnsupportedCPUMarkersAreRejected() {
        for marker in ["ppc64el", "s390x", "armel", "loong64"] {
            for architecture in [CPUArchitecture.arm64, .x86_64] {
                XCTAssertNil(pick(["tool-macos-\(marker).dmg"], architecture), marker)
            }
        }
    }

    func testX86_64AssetsSurviveTheUnsupportedCPUList() {
        // A bare "x86" marker would also match inside "x86_64".
        XCTAssertNotNil(pick(["tool-macos-x86_64.dmg"], .x86_64))
    }

    func testEachProgramOfAMultiProgramReleaseIsSelectable() throws {
        let hauntware = assets(ReleaseSelectionTests.hauntwareAssets)
        let cases: [(String, CPUArchitecture, String?)] = [
            ("planchette", .arm64, "planchette-macos-universal.zip"),
            ("poltergeist", .x86_64, "poltergeist-macos-universal.zip"),
            ("seance", .arm64, "seance-macos-universal.zip"),
            ("seance", .x86_64, "seance-macos-universal.zip"),
            // Shipped for Apple Silicon only on macOS, so an Intel Mac has nothing.
            ("seance-sync", .arm64, "seance-sync-macos-arm64.tar.gz"),
            ("seance-sync", .x86_64, nil),
        ]
        for (program, architecture, expected) in cases {
            let filter = try XCTUnwrap(try AssetFilter.parse(program))
            XCTAssertEqual(AssetPicker.compatibleAsset(hauntware, filter: filter, architecture: architecture)?.name,
                           expected, program)
        }
    }

    func testTheWrapperAppliesTheFilterBeforeRanking() throws {
        let list = assets(["planchette-macos-universal.dmg", "seance-macos-universal.dmg",
                           "seance-sync-macos-universal.dmg"])
        XCTAssertEqual(AssetPicker.compatibleAsset(list, filter: nil)?.name, "planchette-macos-universal.dmg")
        XCTAssertEqual(AssetPicker.compatibleAsset(list, filter: try AssetFilter.parse("Seance"))?.name,
                       "seance-macos-universal.dmg")
        XCTAssertNil(AssetPicker.compatibleAsset(list, filter: try AssetFilter.parse("poltergeist")))
    }
}
