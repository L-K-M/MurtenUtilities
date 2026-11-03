import XCTest
@testable import RunningManCore

/// The suite's background check discovers runners with privacy-protected folders
/// excluded; anything there is reported as skipped, never read.
final class DiscoveryExclusionTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("runningman-exclusion-" + UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: home)
    }

    func testCandidatesInsideExcludedFoldersAreSkippedAndReported() async throws {
        let documents = home.appendingPathComponent("Documents")
        let protected = documents.appendingPathComponent("protected-runner")
        let imported = documents.appendingPathComponent("imported-runner")
        let visible = home.appendingPathComponent("actions-runners/visible-runner")
        for directory in [protected, imported, visible] { try writeGitHubRunner(at: directory) }
        try writeAgent(label: "actions.runner.example.protected", workingDirectory: protected)

        let discovery = RunnerDiscovery(homeDirectory: home, excludedFolders: [documents])
        let result = await discovery.discover(additionalDirectories: [imported])

        XCTAssertEqual(result.runners.map(\.directory.path), [visible.path])
        XCTAssertEqual(Set(result.skippedDirectories.map(\.path)), [protected.path, imported.path])
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testWithoutExclusionsTheSameFoldersAreDiscovered() async throws {
        let protected = home.appendingPathComponent("Documents/protected-runner")
        try writeGitHubRunner(at: protected)
        try writeAgent(label: "actions.runner.example.protected", workingDirectory: protected)

        let result = await RunnerDiscovery(homeDirectory: home).discover()

        XCTAssertEqual(result.runners.map(\.directory.path), [protected.path])
        XCTAssertTrue(result.skippedDirectories.isEmpty)
    }

    func testForgejoServiceInsideAnExcludedFolderIsNotResolved() async throws {
        let documents = home.appendingPathComponent("Documents")
        let target = home.appendingPathComponent("elsewhere/forgejo")
        let link = documents.appendingPathComponent("forgejo-link")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let executable = target.appendingPathComponent("forgejo-runner")
        try writeAgent(label: "ch.lkmc.RunningMan.forgejo.example", workingDirectory: link,
                       arguments: [executable.path, "daemon", "--config", link.appendingPathComponent("config.yaml").path])

        let result = await RunnerDiscovery(homeDirectory: home, excludedFolders: [documents]).discover()

        XCTAssertTrue(result.runners.isEmpty)
        XCTAssertEqual(result.skippedDirectories.map(\.path), [link.path], "The link is reported as written, not followed")
    }

    // MARK: - Fixtures

    private func writeGitHubRunner(at directory: URL) throws {
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try Data("{\"agentName\":\"\(directory.lastPathComponent)\"}".utf8).write(to: directory.appendingPathComponent(".runner"))
        try Data().write(to: directory.appendingPathComponent("bin/Runner.Listener"))
    }

    private func writeAgent(label: String, workingDirectory: URL, arguments: [String]? = nil) throws {
        let agents = home.appendingPathComponent("Library/LaunchAgents")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let properties: [String: Any] = [
            "Label": label, "WorkingDirectory": workingDirectory.path,
            "ProgramArguments": arguments ?? [workingDirectory.appendingPathComponent("runsvc.sh").path]
        ]
        try PropertyListSerialization.data(fromPropertyList: properties, format: .xml, options: 0)
            .write(to: agents.appendingPathComponent(label + ".plist"))
    }
}
