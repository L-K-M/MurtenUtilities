import Foundation
import XCTest
import DoctorCore
@testable import DeviceControlDoctorModule

/// Answers commands from fixture output and records every call. Never
/// spawns a process, so no test reads or changes the live permission state.
final class FakeProcessRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [[String]: CommandResult] = [:]
    private var recorded: [[String]] = []
    private var cancelsCallingTask = false

    var calls: [[String]] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    func respond(to command: [String], with result: CommandResult) {
        lock.lock(); defer { lock.unlock() }
        responses[command] = result
    }

    /// Cancels the task that makes the next call, as the coordinator does
    /// when a watcher is switched off mid-poll.
    func cancelCallingTask() {
        lock.lock(); defer { lock.unlock() }
        cancelsCallingTask = true
    }

    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async -> CommandResult {
        let command = [executable] + arguments
        let (response, cancel) = record(command)
        if cancel { withUnsafeCurrentTask { $0?.cancel() } }
        return response ?? CommandResult(output: "No fixture for \(command.joined(separator: " "))", exitCode: 127)
    }

    private func record(_ command: [String]) -> (CommandResult?, cancel: Bool) {
        lock.lock(); defer { lock.unlock() }
        recorded.append(command)
        return (responses[command], cancelsCallingTask)
    }

    // MARK: - tccutil and codesign fixtures

    /// The help text of a macOS that offers `tccutil list` (verified on 27.2).
    func offerListing() {
        respond(to: [SystemTool.tccutil], with: CommandResult(
            output: "Usage: tccutil reset SERVICE [BUNDLE_ID]\n       tccutil list -s SERVICE [-b BUNDLE_ID]", exitCode: 64))
    }

    /// The help text of a macOS without `tccutil list`, such as macOS 26.
    func withholdListing() {
        respond(to: [SystemTool.tccutil], with: CommandResult(output: "Usage: tccutil reset SERVICE [BUNDLE_ID]", exitCode: 64))
    }

    func report(_ service: PermissionService, for bundleID: String, _ output: String, exitCode: Int32, timedOut: Bool = false) {
        respond(to: [SystemTool.tccutil, "list", "-s", service.rawValue, "-b", bundleID],
                with: CommandResult(output: output, exitCode: exitCode, timedOut: timedOut))
    }

    func sign(_ path: String, team: String = FixtureMac.team, valid: Bool = true) {
        let display = """
            Executable=\(path)/Contents/MacOS/Example
            Identifier=com.example.App
            Format=app bundle with Mach-O universal (x86_64 arm64)
            TeamIdentifier=\(team)
            designated => identifier "com.example.App" and anchor apple generic and certificate leaf[subject.OU] = \(team)
            """
        respond(to: [SystemTool.codesign, "--display", "--verbose=2", "-r", "-", path],
                with: CommandResult(output: display, exitCode: 0))
        respond(to: [SystemTool.codesign, "--verify", "--strict", "--verbose=2", path],
                with: CommandResult(output: valid ? "\(path): valid on disk" : "\(path): invalid signature", exitCode: valid ? 0 : 1))
    }

    var ranReset: Bool {
        calls.contains { $0.first == SystemTool.tccutil && $0.dropFirst().first == "reset" }
    }
}

/// A temporary folder standing in for the Mac: app bundles, a home folder
/// and the watch list file.
final class FixtureMac {
    static let team = "TEAMID1234"

    let root: URL
    let home: URL
    let watchList: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("DeviceControlDoctorModuleTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        root = base.resolvingSymlinksInPath()
        home = root.appendingPathComponent("home")
        watchList = home.appendingPathComponent("Library/Application Support/DeviceControlDoctor/watchlist.json")
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Writes `<folder>/<name>.app` with an Info.plist and returns it as the
    /// pane would add it.
    func installApp(_ name: String, bundleID: String, in folder: String = "Applications",
                    expecting services: [PermissionService] = [.accessibility]) throws -> WatchedApp {
        let bundle = root.appendingPathComponent(folder).appendingPathComponent("\(name).app")
        try writeInfo(bundleID: bundleID, name: name, at: bundle)
        var app = try XCTUnwrap(AppCatalog.app(at: bundle))
        app.expectedServices = services
        app.identity = Self.signedIdentity()
        return app
    }

    func writeInfo(bundleID: String, name: String, at bundle: URL) throws {
        let contents = bundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": name, "CFBundleShortVersionString": "1.0"]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
    }

    func saveWatchList(_ apps: [WatchedApp]) throws {
        try WatchListFile.write(apps: apps, events: [], to: watchList)
    }

    /// The baseline the pane saves after a check of a validly signed app.
    static func signedIdentity(team: String = team) -> AppIdentity {
        var identity = AppIdentity()
        identity.signingIdentifier = "com.example.App"
        identity.teamIdentifier = team
        identity.requirement = "identifier \"com.example.App\" and anchor apple generic and certificate leaf[subject.OU] = \(team)"
        identity.signatureValid = true
        identity.signatureDetail = "valid on disk"
        return identity
    }
}
