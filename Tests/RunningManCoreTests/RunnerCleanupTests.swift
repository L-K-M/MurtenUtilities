import XCTest
@testable import RunningManCore

final class RunnerCleanupTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("cleanup-core-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func write(_ text: String, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    private func receipt(id: String = UUID().uuidString, status: RunnerCleanupStatus = .success, path: String = "/synthetic/job-scratch") -> RunnerCleanupRecord {
        RunnerCleanupRecord(id: id, runnerID: "untrusted", repository: "example/desktop", runID: "123", runAttempt: "1", job: "release", runURL: URL(string: "https://github.com/example/desktop/actions/runs/123"), startedAt: Date(timeIntervalSince1970: 100), finishedAt: status == .pending ? nil : Date(timeIntervalSince1970: 200), status: status, bytesRemoved: status == .pending ? 0 : 8192, filesRemoved: status == .pending ? 0 : 3, paths: [RunnerCleanupPath(path: path, status: status, bytesRemoved: status == .pending ? 0 : 8192, filesRemoved: status == .pending ? 0 : 3)])
    }
    private func save(_ receipt: RunnerCleanupRecord, in work: URL) throws -> URL {
        let url = work.appendingPathComponent(".runningman-cleanup/\(receipt.id).json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(receipt).write(to: url)
        return url
    }
    func testGitHubWorkFolderDiscoveryAndBackwardCompatibleModel() async throws {
        let directory = root.appendingPathComponent("runner")
        try write("", directory.appendingPathComponent("bin/Runner.Listener"))
        try write(#"{"agentName":"example","workFolder":"jobs"}"#, directory.appendingPathComponent(".runner"))
        let found = await RunnerDiscovery(homeDirectory: root).discover()
        XCTAssertEqual(found.runners.first?.workDirectoryURL, directory.appendingPathComponent("jobs"))
        try write(#"{"agentName":"example","workFolder":"/synthetic/external-work"}"#, directory.appendingPathComponent(".runner"))
        let absolute = await RunnerDiscovery(homeDirectory: root).discover()
        XCTAssertEqual(absolute.runners.first?.workDirectoryURL?.path, "/synthetic/external-work")
        try write(#"{"agentName":"example"}"#, directory.appendingPathComponent(".runner"))
        let fallback = await RunnerDiscovery(homeDirectory: root).discover()
        XCTAssertEqual(fallback.runners.first?.workDirectoryURL, directory.appendingPathComponent("_work"))
        let old = try JSONDecoder().decode(InstalledRunner.self, from: Data(#"{"name":"example","directory":"file:///synthetic/runner"}"#.utf8))
        XCTAssertNil(old.workDirectoryURL)
        XCTAssertEqual(try JSONDecoder().decode(InstalledRunner.self, from: JSONEncoder().encode(found.runners[0])), found.runners[0])
    }
    func testReadOnlyReceiptScanBindsRunnerAndRetainsPendingWithoutInferringSuccess() async throws {
        let work = root.appendingPathComponent("custom-work")
        let runner = InstalledRunner(name: "example", directory: root.appendingPathComponent("runner"), workDirectoryURL: work)
        let external = root.appendingPathComponent("untouched"); try write("keep", external)
        let pending = receipt(status: .pending, path: external.path)
        let pendingURL = try save(pending, in: work)
        let completed = receipt()
        _ = try save(completed, in: work)
        let before = try Data(contentsOf: pendingURL)
        let monitor = RunnerCleanupMonitor()
        let result = await monitor.scan(runners: [runner])
        XCTAssertTrue(result.warnings.isEmpty); XCTAssertEqual(result.records.count, 2)
        XCTAssertTrue(result.records.allSatisfy { $0.runnerID == runner.id })
        XCTAssertEqual(result.records.first { $0.id == pending.id }?.status, .pending)
        XCTAssertNil(result.records.first { $0.id == pending.id }?.finishedAt)
        XCTAssertEqual(try Data(contentsOf: pendingURL), before)
        XCTAssertEqual(try String(contentsOf: external, encoding: .utf8), "keep")
        let again = await monitor.scan(runners: [runner]); XCTAssertEqual(again.records, result.records)
    }
    func testReceiptReaderRejectsSymlinksMalformedCountersAndCredentialURLsAndRedacts() async throws {
        let work = root.appendingPathComponent("_work")
        let runner = InstalledRunner(name: "example", directory: root)
        var valid = receipt(); valid.message = "token=PRIVATE_VALUE"
        valid.runURL = URL(string: "https://user:password@github.com/example/desktop?token=PRIVATE_VALUE")
        _ = try save(valid, in: work)
        var bad = receipt(); bad.bytesRemoved = -1
        _ = try save(bad, in: work)
        var missingCompletion = receipt(); missingCompletion.finishedAt = nil
        _ = try save(missingCompletion, in: work)
        var falsePending = receipt(status: .pending); falsePending.filesRemoved = 1
        _ = try save(falsePending, in: work)
        var invalidRun = receipt(); invalidRun.runID = "not-a-run"
        _ = try save(invalidRun, in: work)
        var inconsistent = receipt(); inconsistent.paths[0].status = .failed
        _ = try save(inconsistent, in: work)
        let outside = root.appendingPathComponent("outside.json")
        try write("do not read", outside)
        try FileManager.default.createSymbolicLink(at: work.appendingPathComponent(".runningman-cleanup/\(UUID().uuidString).json"), withDestinationURL: outside)
        let result = await RunnerCleanupMonitor().scan(runners: [runner])
        XCTAssertEqual(result.records.count, 1); XCTAssertNil(result.records[0].runURL)
        XCTAssertFalse(result.records[0].message!.contains("PRIVATE_VALUE")); XCTAssertFalse(result.warnings.isEmpty)
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "do not read")
    }
    func testUnicodeReceiptMessagesAreRedactedAndBoundedForDisplay() async throws {
        let runner = InstalledRunner(name: "example", directory: root)
        var large = receipt()
        large.message = "token=PRIVATE_VALUE " + String(repeating: "🔥", count: 6000)
        large.paths[0].message = "token=PATH_PRIVATE " + String(repeating: "a\u{0301}", count: 4000)
        let file = try save(large, in: root.appendingPathComponent("_work"))
        let original = try Data(contentsOf: file)
        let result = await RunnerCleanupMonitor().scan(runners: [runner])
        XCTAssertTrue(result.warnings.isEmpty)
        let record = try XCTUnwrap(result.records.first)
        XCTAssertLessThanOrEqual(record.message!.utf8.count, 2048)
        XCTAssertLessThanOrEqual(record.paths[0].message!.utf8.count, 1024)
        XCTAssertFalse(record.message!.contains("PRIVATE_VALUE"))
        XCTAssertFalse(record.paths[0].message!.contains("PATH_PRIVATE"))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
    func testReceiptScanCapsLatestHistoryAndSkipsForgejoWithoutReadingConfig() async throws {
        let runner = InstalledRunner(name: "example", directory: root)
        let work = root.appendingPathComponent("_work")
        for index in 0..<110 {
            let file = try save(receipt(), in: work)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(index))], ofItemAtPath: file.path)
        }
        let result = await RunnerCleanupMonitor().scan(runners: [runner])
        XCTAssertEqual(result.records.count, 100)
        let forgejo = InstalledRunner(name: "native", directory: root, provider: .forgejo, configurationURL: root.appendingPathComponent("config.yaml"))
        try write("must not be read", forgejo.configurationURL!)
        let ignored = await RunnerCleanupMonitor().scan(runners: [forgejo]); XCTAssertTrue(ignored.records.isEmpty)
    }
}
