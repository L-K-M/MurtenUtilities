import XCTest
@testable import RepoMenCore

/// Background work must never read inside a privacy-protected folder. These pin
/// the classification, which runs before anything is looked up on disk.
final class ProtectedLocationsTests: XCTestCase {

    private let home = "/Users/test"
    private var roots: [String] { ProtectedLocations.roots(home: home) }

    func testRootsCoverTheFoldersMacOSGuards() {
        for path in ["/Users/test/Desktop", "/Users/test/Documents/GitHub/app",
                     "/Users/test/Downloads", "/Users/test/Library/Mobile Documents/com~apple~CloudDocs/x",
                     "/Users/test/Library/CloudStorage/Dropbox/code", "/Volumes/External/dev",
                     "/System/Volumes/Data/Users/test/Documents/dev"] {
            XCTAssertTrue(ProtectedLocations.contains(path, roots: roots), path)
        }
        for path in ["/Users/test/Developer", "/Users/test/DocumentsArchive", "/Users/test/code/Documents",
                     "/Users/test/Library/Caches", "/opt/src"] {
            XCTAssertFalse(ProtectedLocations.contains(path, roots: roots), path)
        }
    }

    func testContainmentFoldsCaseLikeAPFS() {
        XCTAssertTrue(ProtectedLocations.contains("/users/TEST/documents/app", roots: roots))
        XCTAssertTrue(ProtectedLocations.contains("/volumes/usb", roots: roots))
    }

    func testPlainPathsClassifyWithoutLinks() {
        XCTAssertEqual(ProtectedLocations.classify("/Users/test/dev/app", roots: roots, readLink: { _ in nil }),
                       .allowed)
        XCTAssertEqual(ProtectedLocations.classify("/Users/test/Documents/app", roots: roots, readLink: { _ in nil }),
                       .protected(root: "/Users/test/Documents"))
    }

    func testSymlinkIntoAProtectedFolderIsProtected() {
        let links = ["/Users/test/code": "/Users/test/Documents/code"]
        XCTAssertEqual(ProtectedLocations.classify("/Users/test/code/app", roots: roots,
                                                   readLink: { links[$0] }),
                       .protected(root: "/Users/test/Documents"))
    }

    func testRelativeLinksAndDotDotResolve() {
        let links = ["/Users/test/dev": "../test/Downloads/dev"]
        XCTAssertEqual(ProtectedLocations.classify("/Users/test/dev/x", roots: roots, readLink: { links[$0] }),
                       .protected(root: "/Users/test/Downloads"))
        XCTAssertEqual(ProtectedLocations.classify("/Users/test/dev2/../Desktop/x", roots: roots,
                                                   readLink: { _ in nil }),
                       .protected(root: "/Users/test/Desktop"))
    }

    func testNeverReadsLinksInsideAProtectedFolder() {
        var asked: [String] = []
        _ = ProtectedLocations.classify("/Users/test/Documents/a/b/c", roots: roots) { path in
            asked.append(path)
            return nil
        }
        XCTAssertEqual(asked, ["/Users", "/Users/test"],
                       "classification stops at the protected prefix, before looking inside")
    }

    func testLinkLoopsAreUnresolvable() {
        let links = ["/Users/test/a": "/Users/test/b", "/Users/test/b": "/Users/test/a"]
        XCTAssertEqual(ProtectedLocations.classify("/Users/test/a/x", roots: roots, readLink: { links[$0] }),
                       .unresolvable)
    }

    func testLiveLinksResolveOnDisk() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("ProtectedLocations-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: base) }
        let guarded = base.appendingPathComponent("Guarded")
        try fm.createDirectory(at: guarded.appendingPathComponent("code"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: base.appendingPathComponent("code"),
                                  withDestinationURL: guarded.appendingPathComponent("code"))

        XCTAssertEqual(ProtectedLocations.classify(base.appendingPathComponent("code").path,
                                                   roots: [guarded.path]),
                       .protected(root: guarded.path))
        XCTAssertEqual(ProtectedLocations.classify(base.path, roots: [guarded.path]), .allowed)
    }
}
