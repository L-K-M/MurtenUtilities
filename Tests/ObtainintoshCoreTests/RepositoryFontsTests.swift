import XCTest
@testable import ObtainintoshCore

final class RepositoryFontsTests: XCTestCase {
    private func fonts(_ paths: [String]) -> RepositoryFonts? {
        RepositoryFonts.fromTree(paths.map { RepositoryTree.Entry(path: $0, kind: "blob", size: 2048) }) {
            "https://raw.invalid/\($0)"
        }
    }

    func testKeepsOnlyFontFiles() throws {
        let fonts = try XCTUnwrap(fonts(["C64-Keyboard.zip", "fonts/C64Keyboard-Regular.woff2",
                                         "fonts/C64Keyboard-Regular.otf", "fonts/C64Keyboard-Regular.ttf",
                                         "specimen.png"]))

        XCTAssertEqual(fonts.files.map(\.name), ["C64Keyboard-Regular.otf", "C64Keyboard-Regular.ttf"])
        XCTAssertEqual(fonts.files[1].browserDownloadURL, "https://raw.invalid/fonts/C64Keyboard-Regular.ttf")
        XCTAssertEqual(fonts.names(), ["c64keyboard-regular"])
        // TrueType ranks first among the formats of one font.
        XCTAssertEqual(try fonts.pick(filter: nil).name, "C64Keyboard-Regular.ttf")
    }

    func testARepositoryWithoutFontsOffersNothing() {
        XCTAssertNil(fonts(["README.md", "src/main.rs"]))
        // A directory named like a font is not one.
        XCTAssertNil(RepositoryFonts.fromTree([RepositoryTree.Entry(path: "Inter.ttf", kind: "tree", size: 0)]) { $0 })
    }

    func testTheShallowestCopyOfAFontWins() throws {
        let fonts = try XCTUnwrap(fonts(["docs/site/fonts/Inter.ttf", "fonts/Inter.ttf"]))
        XCTAssertEqual(try fonts.pick(filter: nil).browserDownloadURL, "https://raw.invalid/fonts/Inter.ttf")
    }

    func testAFilterChoosesAmongSeveralFonts() throws {
        let fonts = try XCTUnwrap(fonts(["fonts/Inter-Bold.ttf", "fonts/Inter-Regular.ttf",
                                         "fonts/InterDisplay-Regular.otf"]))

        XCTAssertEqual(fonts.names(), ["inter-bold", "inter-regular", "interdisplay-regular"])
        XCTAssertEqual(try fonts.pick(filter: .program("inter-regular")).name, "Inter-Regular.ttf")
        XCTAssertThrowsError(try fonts.pick(filter: .program("inter-light"))) { error in
            XCTAssertTrue("\(error)".hasSuffix(
                "\"inter-light\". Its fonts: inter-bold, inter-regular, interdisplay-regular"), "\(error)")
        }
    }

    func testParsesBothForgesTreeListings() throws {
        let github = """
        {"sha": "abc", "truncated": false, "tree": [
            {"path": "fonts", "mode": "040000", "type": "tree", "sha": "d"},
            {"path": "fonts/A.ttf", "mode": "100644", "type": "blob", "sha": "e", "size": 23572}
        ]}
        """
        let forgejo = """
        {"sha": "abc", "truncated": true, "page": 1, "total_count": 7,
         "tree": [{"path": "A.otf", "mode": "100644", "type": "blob", "size": 4116, "sha": "f"}]}
        """

        let githubTree = try JSONDecoder().decode(RepositoryTree.self, from: Data(github.utf8))
        let forgejoTree = try JSONDecoder().decode(RepositoryTree.self, from: Data(forgejo.utf8))

        XCTAssertEqual(githubTree.tree.count, 2)
        XCTAssertEqual(githubTree.tree[1].size, 23572)
        XCTAssertNil(githubTree.totalCount)
        XCTAssertEqual(forgejoTree.totalCount, 7)
        XCTAssertEqual(forgejoTree.tree[0].kind, RepositoryTree.Entry.fileKind)
    }
}
