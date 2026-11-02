import XCTest
@testable import DoctorCore

final class ProtectedLocationTests: XCTestCase {
    private let home = "/Users/example"

    func testPrivacyGuardedFoldersAreProtected() {
        for path in ["/Users/example/Desktop/Tool.app",
                     "/Users/example/Documents/Tools/Tool.app",
                     "/Users/example/Downloads/Tool.app",
                     "/Users/example/Library/Mobile Documents/com~apple~CloudDocs/Tool.app",
                     "/Users/example/Library/CloudStorage/Dropbox/Tool.app",
                     "/Users/example/Library/Containers/com.example.Host/Data/Tool.app",
                     "/Users/example/Library/Group Containers/group.example/Tool.app",
                     "/Volumes/External/Applications/Tool.app"] {
            XCTAssertTrue(ProtectedLocation.contains(path, home: home), path)
        }
    }

    func testUnknownHomeFoldersAreTreatedAsProtected() {
        XCTAssertTrue(ProtectedLocation.contains("/Users/example/Tool.app", home: home))
        XCTAssertTrue(ProtectedLocation.contains("/Users/example/Applications2/Tool.app", home: home))
        XCTAssertTrue(ProtectedLocation.contains("/Users/example/Pictures/Tool.app", home: home))
    }

    func testApplicationFoldersAreReadable() {
        for path in ["/Applications/Tool.app",
                     "/Applications/Utilities/Tool.app",
                     "/System/Applications/Tool.app",
                     "/Users/example/Applications/Tool.app",
                     "/Users/example/Library/Application Support/Host/Helper.app",
                     "/private/var/folders/xy/T/Fixture/Tool.app",
                     "/Users/other/Applications/Tool.app"] {
            XCTAssertFalse(ProtectedLocation.contains(path, home: home), path)
        }
    }

    // MARK: - Links

    private func resolve(_ path: String, links: [String: String]) -> (path: String?, looked: [String]) {
        var looked: [String] = []
        let result = ProtectedLocation.readablePath(path, home: home) { candidate in
            looked.append(candidate)
            return links[candidate]
        }
        return (result, looked)
    }

    func testPathWithoutLinksIsReturnedAsIs() {
        let result = resolve("/Applications/Tool.app", links: [:])
        XCTAssertEqual(result.path, "/Applications/Tool.app")
        XCTAssertEqual(result.looked, ["/Users", "/Users/example", "/Applications", "/Applications/Tool.app"],
                       "home's own components, then the path's, one at a time")
        XCTAssertEqual(resolve("/Users/example/Applications/Tool.app", links: [:]).path,
                       "/Users/example/Applications/Tool.app", "home itself may be passed on the way to a safe folder")
    }

    func testLinkIntoAGuardedFolderIsRefusedWithoutLookingInside() {
        let result = resolve("/Applications/Tool.app", links: ["/Applications/Tool.app": "/Users/example/Downloads/Tool.app"])
        XCTAssertNil(result.path)
        XCTAssertFalse(result.looked.contains { $0.hasPrefix("/Users/example/Downloads") })
    }

    func testLinkedFolderIntoAGuardedFolderIsRefused() {
        let links = ["/Users/example/Applications": "Documents/Apps"]
        XCTAssertNil(resolve("/Users/example/Applications/Tool.app", links: links).path)
    }

    func testLinksBetweenSafeFoldersResolve() {
        let links = ["/Applications/Tool.app": "../opt/tools/Tool.app", "/opt": "/private/opt"]
        XCTAssertEqual(resolve("/Applications/Tool.app", links: links).path, "/private/opt/tools/Tool.app")
    }

    func testHomeBehindALinkIsComparedAfterResolving() {
        // macOS: /var is a link to /private/var.
        let links = ["/var": "private/var"]
        let downloads = ProtectedLocation.readablePath("/private/var/u/Downloads/T.app", home: "/var/u") { links[$0] }
        XCTAssertNil(downloads)
        let applications = ProtectedLocation.readablePath("/var/u/Applications/T.app", home: "/var/u") { links[$0] }
        XCTAssertEqual(applications, "/private/var/u/Applications/T.app")
    }

    func testLinkLoopsAreRefused() {
        let links = ["/Applications/A.app": "/Applications/B.app", "/Applications/B.app": "/Applications/A.app"]
        XCTAssertNil(resolve("/Applications/A.app", links: links).path)
    }

    func testTrailingSlashesDoNotChangeTheAnswer() {
        XCTAssertFalse(ProtectedLocation.contains("/Users/example/Applications/Tool.app/", home: home + "/"))
        XCTAssertTrue(ProtectedLocation.contains("/Users/example/Desktop/Tool.app/", home: home + "/"))
    }
}
