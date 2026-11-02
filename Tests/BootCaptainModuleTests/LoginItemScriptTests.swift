import XCTest
@testable import BootCaptainModule

/// A login item's path is untrusted data: it must reach AppleScript only as
/// a run-handler argument, never as script source.
final class LoginItemScriptTests: XCTestCase {
    private let hostile = #"/Applications/x" & (do shell script "touch /tmp/pwned") & "\.app"#

    func testRemovalPassesThePathAsAnArgumentOnly() throws {
        let arguments = try XCTUnwrap(LoginItemScript.removal(path: hostile))
        XCTAssertEqual(arguments.last, hostile)
        XCTAssertFalse(arguments.dropLast().contains { $0.contains("pwned") || $0.contains("/Applications") })
        XCTAssertTrue(arguments.contains { $0.contains("delete (every login item whose path is itemPath)") })
    }

    func testRestorationPassesThePathAsAnArgumentOnly() throws {
        let arguments = try XCTUnwrap(LoginItemScript.restoration(path: hostile))
        XCTAssertEqual(arguments.last, hostile)
        XCTAssertFalse(arguments.dropLast().contains { $0.contains("pwned") || $0.contains("/Applications") })
    }

    func testOnlyAbsolutePathsAreAccepted() {
        XCTAssertNil(LoginItemScript.removal(path: "-e"))
        XCTAssertNil(LoginItemScript.restoration(path: "relative/App.app"))
        XCTAssertNotNil(LoginItemScript.removal(path: "/Applications/App.app"))
    }
}
