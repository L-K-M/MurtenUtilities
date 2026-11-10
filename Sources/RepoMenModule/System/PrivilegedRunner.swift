import Foundation
import RepoMenCore

/// Runs a short POSIX-sh script as root via AppleScript's
/// `do shell script … with administrator privileges` — macOS shows its standard
/// admin-password dialog (naming osascript, which performs the request), and the
/// user can cancel it. For a non-sandboxed, directly-distributed app this is the
/// narrowest privileged bridge there is: one prompt, one script, no helper tool or
/// daemon installed or left behind.
///
/// Only the vetted script builders may pass through here: `SystemScanner.probeScript`
/// and `SystemReclaimer.script(for:)` (every path they embed comes from the
/// `SystemAreas` catalog or is validated against it first), and — as a fallback
/// used only when an unprivileged run was refused — `SnapshotTool.privilegedScript`
/// and `SnapshotTool.privilegedDeleteScript` (a whitelisted `tmutil` verb with
/// validated operands). Every embedded word is quoted with `shellQuote`.
enum PrivilegedRunner {

    enum Failure: Error, Equatable, LocalizedError {
        /// The user dismissed the password dialog — expected, never alert-worthy.
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: return "Administrator authorization was cancelled."
            case .failed(let message): return message
            }
        }
    }

    /// Runs `script` as root and returns its stdout. Task cancellation terminates
    /// the osascript process (taking a pending password dialog down with it) and
    /// removes the run's keep-going file, which is what stops the script itself.
    static func run(script: String) async throws -> String {
        try await run(script: script, privileges: .administrator)
    }

    /// Whose rights the script runs with. `.currentUser` exists so a test can
    /// drive the real osascript bridge, cancellation included, without a
    /// password dialog.
    enum Privileges {
        case administrator
        case currentUser
    }

    // MARK: Stopping a running script

    /// The sh variable every script gets: the path of a file that exists for
    /// as long as the run may continue.
    static let keepGoingVariable = "MURTEN_KEEP_GOING"

    /// sh test that holds until the run is stopped. Terminating osascript does
    /// not stop the shell it started, and this app could not signal a root
    /// shell anyway, so a script that deletes must check this before each step
    /// or Stop would let the rest of the batch run. Unset or missing means
    /// stopped: the check fails safe.
    static let keepGoingTest = "[ -e \"$\(keepGoingVariable)\" ]"

    /// A private directory holding one run's keep-going file. Only its
    /// existence is ever tested, as root, so nothing is read from or written
    /// to a user-writable place with privileges.
    private struct KeepGoingFile: Sendable {
        let directory: URL
        var url: URL { directory.appendingPathComponent("keep-going") }

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("murten-privileged-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                try? FileManager.default.removeItem(at: directory)
                throw CocoaError(.fileWriteUnknown)
            }
        }

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    static func run(script: String, privileges: Privileges) async throws -> String {
        try Task.checkCancellation()
        let keepGoing: KeepGoingFile
        do {
            keepGoing = try KeepGoingFile()
        } catch {
            throw Failure.failed("Could not prepare the privileged run: \(error.localizedDescription)")
        }
        // Also when the run ends by itself: nothing it started may go on
        // working once the caller has its answer.
        defer { keepGoing.remove() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = appleScriptArguments(
            for: "\(keepGoingVariable)=\(shellQuote(keepGoing.url.path))\n\(script)",
            privileges: privileges)
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    // Drained after exit, which is safe only while the output fits
                    // the pipe buffer (~64 KB): one ~120-byte record per DIRECT
                    // child of the two catalog roots, base64'd — i.e. room for
                    // several hundred children where real systems have a few dozen.
                    // A child that overran it would block writing and never exit;
                    // Stop still recovers (onCancel terminates it). Keep the probe's
                    // output per-child — never per-file — and that margin holds.
                    let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(),
                                     encoding: .utf8) ?? ""
                    let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(),
                                     encoding: .utf8) ?? ""
                    if finished.terminationStatus == 0 {
                        continuation.resume(returning: out)
                    } else if err.contains("-128") {   // AppleScript "User canceled."
                        continuation.resume(throwing: Failure.cancelled)
                    } else {
                        let reason = err.trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(throwing: Failure.failed(reason.isEmpty
                            ? "The privileged helper exited with status \(finished.terminationStatus)."
                            : reason))
                    }
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: Failure.failed(error.localizedDescription))
                }
            }
        } onCancel: {
            // First the file, so the script stops before its next step even
            // though it outlives osascript.
            keepGoing.remove()
            if process.isRunning { process.terminate() }
        }
    }

    // MARK: Pure helpers (unit-tested; the osascript spawn above is manual-verify)

    /// How long the privileged script may run before AppleScript gives up. The
    /// default Apple event timeout is ~2 minutes, and `do shell script` is
    /// dispatched as an Apple event: measuring 70 GB of log files can take longer
    /// than that and would die with "AppleEvent timed out (-1712)" — the exact case
    /// this feature exists for. An explicit `with timeout` block lifts the ceiling;
    /// the user can still stop early (cancelling the task kills osascript).
    static let timeoutSeconds = 3600

    /// The `osascript` argument list: one `-e` per script line, since AppleScript
    /// string literals cannot hold raw newlines and `with timeout` needs a block.
    static func appleScriptArguments(for script: String,
                                     privileges: Privileges = .administrator) -> [String] {
        let rights = privileges == .administrator ? " with administrator privileges" : ""
        return [
            "-e", "with timeout of \(timeoutSeconds) seconds",
            "-e", "do shell script \"\(escapeForAppleScript(script))\""
                + rights + " without altering line endings",
            "-e", "end timeout",
        ]
    }

    /// Quotes `string` for POSIX sh so it is always ONE literal word — no expansion,
    /// no splitting — whatever bytes the name contains. (NUL is the one byte sh
    /// cannot carry; POSIX paths cannot contain it and `SystemAreas.validate`
    /// rejects it.)
    static func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escapes `script` for embedding in a double-quoted AppleScript string literal
    /// passed via `osascript -e`. Raw newlines are not legal inside AppleScript
    /// string literals, so they become `\n` escapes (supported since AppleScript
    /// 2.0); backslashes are escaped first so the later replacements survive.
    static func escapeForAppleScript(_ script: String) -> String {
        script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    /// Decodes the base64 payload the privileged scripts emit. They pipe their
    /// NUL-separated records through `/usr/bin/base64` because AppleScript strings
    /// cannot round-trip arbitrary bytes (and `do shell script` historically
    /// rewrites line endings) — base64 is pure ASCII and survives anything.
    /// Whitespace-tolerant on the way back in.
    static func decodePayload(_ output: String) -> Data? {
        Data(base64Encoded: String(output.filter { !$0.isWhitespace }))
    }
}
