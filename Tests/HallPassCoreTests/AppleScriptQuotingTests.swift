import Foundation
import Testing
@testable import HallPassCore

/// The privileged service passes the multi-line write script to
/// `do shell script` as an AppleScript string literal. These run such
/// literals through osascript without administrator privileges, so the
/// quoting is pinned by AppleScript itself rather than by a reading of it.
@Suite(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/osascript"), "Requires macOS osascript"))
struct AppleScriptQuotingTests {
    @Test func lineBreaksQuotesAndBackslashesSurviveTheLiteral() throws {
        let script = "first='line \"one\"'\nsecond='back\\slash'\n/usr/bin/printf '%s|%s' \"$first\" \"$second\""
        let result = try echoThroughShell(script)
        #expect(result.status == 0, "\(result.output)")
        #expect(result.output == script + "\n")
    }

    @Test func generatedWriteScriptSurvivesTheLiteral() throws {
        let baseline = try PreferencesSnapshot(configuration: .init(wifi: ["old'value; $(touch /tmp/x)"]))
        let script = try PreferencePlan(baseline: baseline, desired: .example).shellScript()
        let result = try echoThroughShell(script)
        #expect(result.status == 0, "\(result.output)")
        #expect(result.output == script + "\n")
    }

    /// `do shell script "printf '%s' " & quoted form of <literal>` prints the
    /// literal's value unchanged; osascript adds one newline. The source goes
    /// through stdin, as in SystemPreferencesService.
    private func echoThroughShell(_ value: String) throws -> (status: Int32, output: String) {
        let source = "do shell script \"/usr/bin/printf '%s' \" & quoted form of "
            + PreferencePlan.appleScriptString(value) + " without altering line endings"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: Data(source.utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
