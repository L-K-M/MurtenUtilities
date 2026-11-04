import Foundation
import Darwin

struct CommandResult: Sendable {
    var output: String
    var exitCode: Int32
    var timedOut: Bool = false
    var outputTruncated: Bool = false
}

/// The fixed system tools the module runs. Never a path from user input.
enum SystemTool {
    static let tccutil = "/usr/bin/tccutil"
    static let codesign = "/usr/bin/codesign"
}

/// The only subprocess boundary. The pane, the reset path and the watcher
/// take it as a parameter, so tests replace it with fixture output and
/// never touch the live system.
protocol ProcessRunning: Sendable {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async -> CommandResult
}

extension ProcessRunning {
    func run(_ executable: String, _ arguments: [String]) async -> CommandResult {
        await run(executable, arguments, timeout: ProcessRunner.defaultTimeout)
    }
}

/// Only fixed system executables and argument arrays are used. No shell is involved.
/// Cancelling the calling task terminates the child, so a cancelled
/// background check stops its work instead of only no longer awaiting it.
struct ProcessRunner: ProcessRunning {
    static let defaultTimeout: TimeInterval = 8

    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async -> CommandResult {
        let state = RunState()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    let process = Process()
                    let pipe = Pipe()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments
                    process.standardOutput = pipe
                    process.standardError = pipe
                    process.standardInput = FileHandle.nullDevice
                    var environment = ProcessInfo.processInfo.environment
                    environment["LC_ALL"] = "C"
                    process.environment = environment
                    do {
                        guard try state.launch(process) else {
                            continuation.resume(returning: CommandResult(output: "The command was cancelled.", exitCode: -1))
                            return
                        }
                    } catch {
                        continuation.resume(returning: CommandResult(output: error.localizedDescription, exitCode: -1))
                        return
                    }
                    let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
                    timer.schedule(deadline: .now() + timeout)
                    timer.setEventHandler {
                        guard process.isRunning else { return }
                        state.markTimedOut()
                        RunState.stop(process)
                    }
                    timer.resume()
                    var data = Data()
                    var outputTruncated = false
                    // Drain even after the retained-output limit so a full pipe cannot deadlock.
                    while let chunk = try? pipe.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
                        if data.count < 131_072 {
                            let remaining = 131_072 - data.count
                            data.append(chunk.prefix(remaining))
                            if chunk.count > remaining { outputTruncated = true }
                        } else {
                            outputTruncated = true
                        }
                    }
                    process.waitUntilExit()
                    timer.cancel()
                    try? pipe.fileHandleForReading.close()
                    let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: CommandResult(output: output,
                                                                  exitCode: process.terminationStatus,
                                                                  timedOut: state.didTimeOut,
                                                                  outputTruncated: outputTruncated))
                }
            }
        } onCancel: {
            state.cancel()
        }
    }
}

private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private var timedOut = false
    private var cancelled = false
    private var process: Process?

    /// Starts `process` unless the task was cancelled first; false when it was.
    func launch(_ process: Process) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return false }
        try process.run()
        self.process = process
        return true
    }

    func markTimedOut() { lock.lock(); timedOut = true; lock.unlock() }
    var didTimeOut: Bool { lock.lock(); defer { lock.unlock() }; return timedOut }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = self.process
        lock.unlock()
        if let process { Self.stop(process) }
    }

    /// A normal termination request, then SIGKILL if the child ignores it.
    static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}
