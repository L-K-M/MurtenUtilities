import XCTest
@testable import RepoMenModule
@testable import RepoMenCore

/// The pure halves of the privileged bridge: shell quoting, AppleScript escaping,
/// and payload decoding, plus stopping a run, driven through the real osascript
/// bridge with the user's own rights. (Spawning osascript as administrator shows
/// a password dialog and stays a manual-verify item.)
final class PrivilegedRunnerTests: XCTestCase {

    // MARK: Stopping

    /// Terminating osascript does not reach a root shell: this app may not
    /// signal it. Measured on the real administrator bridge, a batch went on
    /// for as long as it liked after Stop. So Stop must reach the script
    /// itself, or the rest of a delete batch would still run.
    ///
    /// The user's own shell would die with osascript, so the script here moves
    /// into its own session to be as unreachable as a root one.
    func testStoppingARunStopsAScriptThatSignalsCannotReach() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("murten-stop-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        func stepsTaken() -> Int {
            (try? FileManager.default.contentsOfDirectory(atPath: directory.path).count) ?? 0
        }

        // Forty steps of a quarter second: ten seconds unless it is stopped.
        let batch = """
            i=0
            while [ $i -lt 40 ]; do
            \(PrivilegedRunner.keepGoingTest) || exit 0
            : > \(PrivilegedRunner.shellQuote(directory.path + "/step"))$i
            sleep 0.25
            i=$((i+1))
            done
            """
        let script = """
            export \(PrivilegedRunner.keepGoingVariable)
            /usr/bin/perl -MPOSIX -e 'POSIX::setsid(); exec "/bin/sh", "-c", $ARGV[0]' \(PrivilegedRunner.shellQuote(batch))
            """
        let run = Task { try await PrivilegedRunner.run(script: script, privileges: .currentUser) }

        let deadline = Date().addingTimeInterval(10)
        while stepsTaken() == 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try XCTSkipIf(stepsTaken() == 0, "osascript cannot run shell scripts in this environment")

        run.cancel()
        _ = try? await run.value
        // One step may already have been under way when Stop arrived.
        try await Task.sleep(nanoseconds: 600_000_000)
        let afterStop = stepsTaken()
        try await Task.sleep(nanoseconds: 1_200_000_000)

        XCTAssertEqual(stepsTaken(), afterStop, "the script kept working after it was stopped")
        XCTAssertLessThan(afterStop, 40)
    }

    func testARunThatIsNotStoppedFinishes() async throws {
        let output = try await PrivilegedRunner.run(
            script: "if \(PrivilegedRunner.keepGoingTest); then printf going; else printf stopped; fi",
            privileges: .currentUser)
        // osascript ends its result with a newline.
        XCTAssertEqual(output.trimmingCharacters(in: .newlines), "going")
    }

    func testOnlyAdministratorRunsAskForPrivileges() {
        XCTAssertTrue(PrivilegedRunner.appleScriptArguments(for: "true")[3]
            .contains("with administrator privileges"))
        XCTAssertFalse(PrivilegedRunner.appleScriptArguments(for: "true", privileges: .currentUser)[3]
            .contains("administrator"))
    }

    // MARK: Pure helpers

    func testShellQuoteWrapsPlainStrings() {
        XCTAssertEqual(PrivilegedRunner.shellQuote("/private/var/root/Library/Logs"),
                       "'/private/var/root/Library/Logs'")
    }

    func testShellQuoteNeutralizesSingleQuotes() {
        XCTAssertEqual(PrivilegedRunner.shellQuote("don't"), "'don'\\''t'")
        XCTAssertEqual(PrivilegedRunner.shellQuote("a'b'c"), "'a'\\''b'\\''c'")
    }

    func testShellQuoteKeepsMetacharactersLiteral() {
        // Everything stays inside single quotes — nothing for sh to expand.
        XCTAssertEqual(PrivilegedRunner.shellQuote("$(rm -rf /) `x` \"y\" \n z"),
                       "'$(rm -rf /) `x` \"y\" \n z'")
    }

    func testAppleScriptEscapingHandlesQuotesBackslashesAndNewlines() {
        XCTAssertEqual(PrivilegedRunner.escapeForAppleScript("say \"hi\""),
                       "say \\\"hi\\\"")
        XCTAssertEqual(PrivilegedRunner.escapeForAppleScript("a\\b"), "a\\\\b")
        XCTAssertEqual(PrivilegedRunner.escapeForAppleScript("line1\nline2"),
                       "line1\\nline2")
        XCTAssertEqual(PrivilegedRunner.escapeForAppleScript("a\tb"), "a\\tb")
    }

    func testAppleScriptEscapingDoesNotDoubleEscape() {
        // A literal backslash-n in the input is an escaped backslash + n on the way
        // out — NOT collapsed with the newline replacement.
        XCTAssertEqual(PrivilegedRunner.escapeForAppleScript("\\n"), "\\\\n")
    }

    func testAppleScriptArgumentsWrapTheScriptInATimeoutBlock() {
        let args = PrivilegedRunner.appleScriptArguments(for: "echo hi\necho there")
        // One -e per line: AppleScript string literals can't hold raw newlines, and
        // `with timeout` must be a block.
        XCTAssertEqual(args.filter { $0 == "-e" }.count, 3)
        XCTAssertEqual(args.first, "-e")
        XCTAssertEqual(args[1], "with timeout of \(PrivilegedRunner.timeoutSeconds) seconds")
        XCTAssertEqual(args.last, "end timeout")

        let command = args[3]
        XCTAssertTrue(command.hasPrefix("do shell script \""))
        XCTAssertTrue(command.contains("with administrator privileges"))
        XCTAssertTrue(command.contains("echo hi\\necho there"),
                      "the embedded script keeps its newlines as escapes")
        XCTAssertFalse(command.contains("\n"),
                       "a raw newline would make the AppleScript literal unparseable")
    }

    func testTimeoutIsGenerousEnoughForAHugeLogTree() {
        // The default Apple event timeout (~2 min) is the failure mode this guards:
        // measuring 70 GB of RTCReporting logs can take longer than that.
        XCTAssertGreaterThan(PrivilegedRunner.timeoutSeconds, 600)
    }

    func testDecodePayloadToleratesWhitespaceAndRejectsGarbage() {
        let data = Data("OK\t/some/path\0".utf8)
        let wrapped = data.base64EncodedString(options: [.lineLength64Characters])
            + "\r\n"
        XCTAssertEqual(PrivilegedRunner.decodePayload(wrapped), data,
                       "base64 line wrapping and CRLFs must not break decoding")
        XCTAssertNil(PrivilegedRunner.decodePayload("definitely not base64 !!!"))
    }
}
