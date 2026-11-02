import XCTest
@testable import DoctorCore

final class TCCOutputParserTests: XCTestCase {
    func test_errorAndAmbiguousTextCannotBecomeAnAuthorization() {
        for output in ["not granted", "granted\ndenied", "Error: query denied", "Permission denied by sandbox", "unlimited", "No grant: previously granted"] {
            for exitCode: Int32 in [0, 1, 2] {
                XCTAssertEqual(TCCOutputParser.parseQuery(output: output, exitCode: exitCode).state, .unknown)
            }
        }
        XCTAssertFalse(TCCOutputParser.supportsListing(help: "blacklist -s SERVICE -b BUNDLE"))
    }

    // MARK: - parseQuery: macOS 27 query fixtures

    func test_granted_outputAndExit0() {
        let result = TCCOutputParser.parseQuery(output: "granted\n", exitCode: 0)
        XCTAssertEqual(result.state, .granted)
        XCTAssertFalse(result.detail.isEmpty)
    }

    func test_denied_outputAndExit1() {
        let result = TCCOutputParser.parseQuery(output: "denied\n", exitCode: 1)
        XCTAssertEqual(result.state, .denied)
        XCTAssertFalse(result.detail.isEmpty)
    }

    func test_limited_outputAndExit2() {
        let result = TCCOutputParser.parseQuery(output: "limited\n", exitCode: 2)
        XCTAssertEqual(result.state, .limited)
        XCTAssertFalse(result.detail.isEmpty)
    }

    // MARK: - parseQuery: success detail is explanatory

    func test_granted_defaultDetail() {
        let result = TCCOutputParser.parseQuery(output: "granted\n", exitCode: 0)
        XCTAssertEqual(result.detail, "Access has been granted")
    }

    func test_denied_defaultDetail() {
        let result = TCCOutputParser.parseQuery(output: "denied\n", exitCode: 1)
        XCTAssertEqual(result.detail, "Access has been denied")
    }

    func test_limited_defaultDetail() {
        let result = TCCOutputParser.parseQuery(output: "limited\n", exitCode: 2)
        XCTAssertEqual(result.detail, "Access is limited")
    }

    // MARK: - parseQuery: conflicting output/status → unknown

    func test_conflicting_grantedOutput_exit1() {
        let result = TCCOutputParser.parseQuery(output: "granted\n", exitCode: 1)
        XCTAssertEqual(result.state, .unknown)
    }

    func test_conflicting_deniedOutput_exit0() {
        let result = TCCOutputParser.parseQuery(output: "denied\n", exitCode: 0)
        XCTAssertEqual(result.state, .unknown)
    }

    func test_conflicting_limitedOutput_exit1() {
        let result = TCCOutputParser.parseQuery(output: "limited\n", exitCode: 1)
        XCTAssertEqual(result.state, .unknown)
    }

    func test_conflicting_grantedOutput_exit2() {
        let result = TCCOutputParser.parseQuery(output: "granted\n", exitCode: 2)
        XCTAssertEqual(result.state, .unknown)
    }

    // MARK: - parseQuery: blank output → unknown

    func test_blankOutput_exit0() {
        let result = TCCOutputParser.parseQuery(output: "", exitCode: 0)
        XCTAssertEqual(result.state, .unknown)
    }

    func test_blankOutput_exit1() {
        let result = TCCOutputParser.parseQuery(output: "   \n  \n", exitCode: 1)
        XCTAssertEqual(result.state, .unknown)
    }

    // MARK: - parseQuery: unknown output text → unknown

    func test_unknownOutputText_exit0() {
        let result = TCCOutputParser.parseQuery(output: "maybe\n", exitCode: 0)
        XCTAssertEqual(result.state, .unknown)
    }

    func test_unknownOutputText_exit99() {
        let result = TCCOutputParser.parseQuery(output: "something weird happened\n", exitCode: 99)
        XCTAssertEqual(result.state, .unknown)
    }

    // MARK: - parseQuery: arbitrary failure exit codes → unknown

    func test_arbitraryExitCode_grantedOutput() {
        let result = TCCOutputParser.parseQuery(output: "granted\n", exitCode: 3)
        XCTAssertEqual(result.state, .unknown)
    }

    func test_arbitraryExitCode_emptyOutput() {
        let result = TCCOutputParser.parseQuery(output: "", exitCode: 42)
        XCTAssertEqual(result.state, .unknown)
    }

    // MARK: - parseQuery: exit 64 → unavailable (usage error)

    func test_exit64_unavailable() {
        let result = TCCOutputParser.parseQuery(output: "Usage: tccutil query ...\n", exitCode: 64)
        XCTAssertEqual(result.state, .unavailable)
    }

    func test_exit64_emptyOutput() {
        let result = TCCOutputParser.parseQuery(output: "", exitCode: 64)
        XCTAssertEqual(result.state, .unavailable)
    }

    // MARK: - parseQuery: exit 77 → unavailable (sandbox)

    func test_exit77_unavailable() {
        let result = TCCOutputParser.parseQuery(output: "Operation not permitted\n", exitCode: 77)
        XCTAssertEqual(result.state, .unavailable)
    }

    func test_exit77_emptyOutput() {
        let result = TCCOutputParser.parseQuery(output: "", exitCode: 77)
        XCTAssertEqual(result.state, .unavailable)
    }

    // MARK: - parseQuery: errors are NOT interpreted as denials

    func test_errorOutput_notDenial() {
        let result = TCCOutputParser.parseQuery(output: "Error: connection refused\n", exitCode: 3)
        XCTAssertEqual(result.state, .unknown)
        XCTAssertNotEqual(result.state, .denied)
    }

    func test_exit77_notDenial() {
        let result = TCCOutputParser.parseQuery(output: "Operation not permitted\n", exitCode: 77)
        XCTAssertEqual(result.state, .unavailable)
        XCTAssertNotEqual(result.state, .denied)
    }

    // MARK: - parseQuery: detail limited to 1200 characters

    func test_detailTruncatedTo1200() {
        let longOutput = String(repeating: "a", count: 1500)
        let result = TCCOutputParser.parseQuery(output: longOutput, exitCode: 99)
        XCTAssertEqual(result.state, .unknown)
        XCTAssertEqual(result.detail.count, 1200)
    }

    // MARK: - parseQuery: case insensitive output matching

    func test_grantedUpperCase() {
        let result = TCCOutputParser.parseQuery(output: "GRANTED\n", exitCode: 0)
        XCTAssertEqual(result.state, .granted)
    }

    func test_deniedMixedCase() {
        let result = TCCOutputParser.parseQuery(output: "Denied\n", exitCode: 1)
        XCTAssertEqual(result.state, .denied)
    }

    // MARK: - parseClients: basic bundle IDs and paths

    func test_parseClients_bundleIDs() {
        let output = "com.macility.popchar3\ncom.example.app\n"
        let clients = TCCOutputParser.parseClients(output: output)
        XCTAssertEqual(clients, ["com.macility.popchar3", "com.example.app"])
    }

    func test_parseClients_absolutePaths() {
        let output = "/Applications/Refine.app/Contents/MacOS/Refine\n/System/Applications/Calculator.app/Contents/MacOS/Calculator\n"
        let clients = TCCOutputParser.parseClients(output: output)
        XCTAssertEqual(clients, [
            "/Applications/Refine.app/Contents/MacOS/Refine",
            "/System/Applications/Calculator.app/Contents/MacOS/Calculator"
        ])
    }

    func test_parseClients_mixedBundleAndPaths() {
        let output = """
        com.macility.popchar3
        /Applications/Refine.app/Contents/MacOS/Refine
        com.apple.Terminal
        """
        let clients = TCCOutputParser.parseClients(output: output)
        XCTAssertEqual(clients, [
            "com.macility.popchar3",
            "/Applications/Refine.app/Contents/MacOS/Refine",
            "com.apple.Terminal"
        ])
    }

    // MARK: - parseClients: deduplication preserves order

    func test_parseClients_deduplicates() {
        let output = """
        com.example.app
        com.macility.popchar3
        com.example.app
        /Applications/Refine.app/Contents/MacOS/Refine
        com.macility.popchar3
        """
        let clients = TCCOutputParser.parseClients(output: output)
        XCTAssertEqual(clients, [
            "com.example.app",
            "com.macility.popchar3",
            "/Applications/Refine.app/Contents/MacOS/Refine"
        ])
    }

    // MARK: - parseClients: skip empty lines

    func test_parseClients_skipEmptyLines() {
        let output = "\ncom.example.app\n\n\ncom.other.app\n"
        let clients = TCCOutputParser.parseClients(output: output)
        XCTAssertEqual(clients, ["com.example.app", "com.other.app"])
    }

    // MARK: - parseClients: skip headings

    func test_parseClients_skipHeadings() {
        let output = """
        granted:
        com.example.app
        denied:
        com.other.app
        """
        let clients = TCCOutputParser.parseClients(output: output)
        XCTAssertEqual(clients, ["com.example.app", "com.other.app"])
    }

    // MARK: - parseClients: skip error/usage text

    func test_parseClients_skipErrorText() {
        let output = """
        error: something went wrong
        com.example.app
        usage: tccutil list ...
        com.other.app
        note: this is a note
        """
        let clients = TCCOutputParser.parseClients(output: output)
        XCTAssertEqual(clients, ["com.example.app", "com.other.app"])
    }

    // MARK: - parseClients: malformed lines are skipped

    func test_parseClients_skipMalformed() {
        let output = """
        com.example.app
        not a valid bundle id
        /Applications/Refine.app/Contents/MacOS/Refine
        just some random text
        123invalid
        """
        let clients = TCCOutputParser.parseClients(output: output)
        XCTAssertEqual(clients, [
            "com.example.app",
            "/Applications/Refine.app/Contents/MacOS/Refine"
        ])
    }

    // MARK: - parseClients: CRLF line endings

    func test_parseClients_crlf() {
        let output = "com.example.app\r\ncom.other.app\r\n"
        let clients = TCCOutputParser.parseClients(output: output)
        XCTAssertEqual(clients, ["com.example.app", "com.other.app"])
    }

    // MARK: - parseClients: empty output

    func test_parseClients_empty() {
        let clients = TCCOutputParser.parseClients(output: "")
        XCTAssertTrue(clients.isEmpty)
    }

    // MARK: - parseClients: double-slash paths rejected

    func test_parseClients_rejectDoubleSlash() {
        let output = "//not-a-safe-path\ncom.example.app\n"
        let clients = TCCOutputParser.parseClients(output: output)
        XCTAssertEqual(clients, ["com.example.app"])
    }

    // MARK: - supportsListing: requires list syntax with -s and -b

    func test_supportsListing_withFlags() {
        let help = "Usage: tccutil list -s <service> -b <bundle-id>\n"
        XCTAssertTrue(TCCOutputParser.supportsListing(help: help))
    }

    func test_supportsListing_flagsReversed() {
        let help = "  list -b <bundle> -s <service>  \n"
        XCTAssertTrue(TCCOutputParser.supportsListing(help: help))
    }

    func test_supportsListing_bareMentionOfList() {
        let help = "This tool can list permissions.\n"
        XCTAssertFalse(TCCOutputParser.supportsListing(help: help))
    }

    func test_supportsListing_listWithOnlyS() {
        let help = "Usage: tccutil list -s <service>\n"
        XCTAssertFalse(TCCOutputParser.supportsListing(help: help))
    }

    func test_supportsListing_listWithOnlyB() {
        let help = "Usage: tccutil list -b <bundle>\n"
        XCTAssertFalse(TCCOutputParser.supportsListing(help: help))
    }

    func test_supportsListing_noListAtAll() {
        let help = "Usage: tccutil query -s <service>\n"
        XCTAssertFalse(TCCOutputParser.supportsListing(help: help))
    }

    func test_supportsListing_empty() {
        XCTAssertFalse(TCCOutputParser.supportsListing(help: ""))
    }

    func test_supportsListing_multiline() {
        let help = """
        tccutil - macOS TCC database utility
        Commands:
          query -s <service> -b <bundle-id>
          list -s <service> -b <bundle-id>
        """
        XCTAssertTrue(TCCOutputParser.supportsListing(help: help))
    }
}
