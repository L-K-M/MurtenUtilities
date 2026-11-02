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

    func testTrailingSlashesDoNotChangeTheAnswer() {
        XCTAssertFalse(ProtectedLocation.contains("/Users/example/Applications/Tool.app/", home: home + "/"))
        XCTAssertTrue(ProtectedLocation.contains("/Users/example/Desktop/Tool.app/", home: home + "/"))
    }
}
