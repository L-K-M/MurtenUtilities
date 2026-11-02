import XCTest
import RunningManCore
@testable import RunningManServices

/// The background check's probe against a temporary home and a fake executor.
final class RunnerHealthProbeTests: XCTestCase {
    private var home: URL!
    private let label = "actions.runner.example-project.probe-mac"

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("runningman-probe-tests-" + UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: home)
    }

    func testReadsStateWithReadOnlyCommandsAndSkipsProtectedFolders() async throws {
        let runner = home.appendingPathComponent("actions-runners/probe-mac")
        let protected = home.appendingPathComponent("Documents/protected-mac")
        try writeGitHubRunner(at: runner, label: label)
        try writeGitHubRunner(at: protected, label: "actions.runner.example-project.protected-mac")
        let fake = FakeExecutor()
        let probe = RunnerHealthProbe(homeDirectory: home, systemDaemonsDirectory: nil, executor: fake, userID: getuid())

        let reading = await probe.read(additionalDirectories: [])

        XCTAssertEqual(reading.snapshots.map(\.runner.directory.path), [runner.path])
        XCTAssertEqual(reading.snapshots.first?.status, .stopped)
        XCTAssertEqual(reading.snapshots.first?.startsAtLogin, true)
        XCTAssertEqual(reading.skippedDirectories.map(\.path), [protected.path])

        let commands = await fake.recorded()
        XCTAssertFalse(commands.isEmpty)
        for command in commands {
            XCTAssertTrue(["/bin/ps", "/bin/launchctl"].contains(command.executable), command.executable)
            if command.executable == "/bin/launchctl" {
                XCTAssertTrue(["list", "print-disabled", "print"].contains(command.arguments.first ?? ""),
                              command.arguments.joined(separator: " "))
            }
        }
    }

    func testARunningListenerReadsAsOnline() async throws {
        let runner = home.appendingPathComponent("actions-runners/probe-mac")
        try writeGitHubRunner(at: runner, label: label)
        let fake = FakeExecutor()
        await fake.configure(processes: "4242 1 \(runner.path)/bin/Runner.Listener run --startuptype service\n")
        let probe = RunnerHealthProbe(homeDirectory: home, systemDaemonsDirectory: nil, executor: fake, userID: getuid())

        let reading = await probe.read(additionalDirectories: [])

        XCTAssertEqual(reading.snapshots.first?.processID, 4242)
        XCTAssertEqual(reading.snapshots.first.map(RunnerHealthState.init), .online)
    }

    func testNoRunnersRunNoCommands() async {
        let fake = FakeExecutor()
        let probe = RunnerHealthProbe(homeDirectory: home, systemDaemonsDirectory: nil, executor: fake, userID: getuid())

        let reading = await probe.read(additionalDirectories: [])

        XCTAssertTrue(reading.snapshots.isEmpty)
        let commands = await fake.recorded()
        XCTAssertTrue(commands.isEmpty)
    }

    // MARK: - Fixtures

    private func writeGitHubRunner(at directory: URL, label: String) throws {
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try Data("{\"agentName\":\"\(directory.lastPathComponent)\",\"gitHubUrl\":\"https://github.com/example/project\"}".utf8)
            .write(to: directory.appendingPathComponent(".runner"))
        for name in ["bin/Runner.Listener", "config.sh", "runsvc.sh"] {
            try Data("#!/bin/bash\nexit 0\n".utf8).write(to: directory.appendingPathComponent(name))
        }
        let agents = home.appendingPathComponent("Library/LaunchAgents")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let plist = agents.appendingPathComponent(label + ".plist")
        let properties: [String: Any] = ["Label": label, "WorkingDirectory": directory.path, "RunAtLoad": true,
                                         "ProgramArguments": [directory.appendingPathComponent("runsvc.sh").path]]
        try PropertyListSerialization.data(fromPropertyList: properties, format: .xml, options: 0).write(to: plist)
        try Data(plist.path.utf8).write(to: directory.appendingPathComponent(".service"))
    }
}
