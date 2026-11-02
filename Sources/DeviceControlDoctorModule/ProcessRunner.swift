import Foundation
import Darwin

struct CommandResult: Sendable {
    var output: String
    var exitCode: Int32
    var timedOut: Bool = false
}

/// Only fixed system executables and argument arrays are used. No shell is involved.
struct ProcessRunner: Sendable {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 8) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let pipe = Pipe()
                let state = TimeoutState()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = pipe
                process.standardInput = FileHandle.nullDevice
                var environment = ProcessInfo.processInfo.environment
                environment["LC_ALL"] = "C"
                process.environment = environment
                do { try process.run() }
                catch {
                    continuation.resume(returning: CommandResult(output: error.localizedDescription, exitCode: -1))
                    return
                }
                let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler {
                    guard process.isRunning else { return }
                    state.markTimedOut()
                    process.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    }
                }
                timer.resume()
                var data = Data()
                // Drain even after the retained-output limit so a full pipe cannot deadlock.
                while let chunk = try? pipe.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
                    if data.count < 131_072 { data.append(chunk.prefix(131_072 - data.count)) }
                }
                process.waitUntilExit()
                timer.cancel()
                try? pipe.fileHandleForReading.close()
                let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: CommandResult(output: output, exitCode: process.terminationStatus, timedOut: state.value))
            }
        }
    }
}

private final class TimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var timedOut = false
    func markTimedOut() { lock.lock(); timedOut = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return timedOut }
}
