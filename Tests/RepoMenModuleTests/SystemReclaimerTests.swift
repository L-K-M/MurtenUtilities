import XCTest
@testable import RepoMenModule
@testable import RepoMenCore

/// The privileged deletion path: what goes into the batch script, and how its
/// per-path verdicts come back out. The runner is injected — no test ever spawns
/// osascript or shows a password dialog.
final class SystemReclaimerTests: XCTestCase {

    private let logsChild = "/private/var/root/Library/Logs/RTCReporting"
    private let cachesChild = "/private/var/root/Library/Caches/com.apple.rtcreporting"

    private func systemItem(_ path: String) -> CleanableItem {
        CleanableItem(label: "Root logs · \(URL(fileURLWithPath: path).lastPathComponent)",
                      kind: .systemLogs, path: path, anchorPaths: [],
                      isKnownCache: true, isSystemArea: true)
    }

    /// STATUS\tPATH records, NUL-separated, base64-armored — what the script emits.
    private func payload(_ statuses: [(String, String)]) -> String {
        statuses
            .map { Data("\($0.0)\t\($0.1)".utf8) + Data([0]) }
            .reduce(Data(), +)
            .base64EncodedString()
    }

    func testScriptChecksVerifiesAndDeletesEachPath() {
        let script = SystemReclaimer.script(for: [logsChild, cachesChild])
        XCTAssertTrue(script.contains("rm -rf -- '\(logsChild)'"))
        XCTAssertTrue(script.contains("rm -rf -- '\(cachesChild)'"))
        XCTAssertTrue(script.contains("if [ -d '\(logsChild)' ] && [ ! -L '\(logsChild)' ]"),
                      "every path is re-checked as root right before rm")
        XCTAssertTrue(script.contains("| /usr/bin/base64"))
    }

    // MARK: Stopping

    /// Runs the real batch script with /bin/sh on two scratch directories.
    private func runScript(stopped: Bool) throws -> (statuses: [String: String], left: [String]) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("murten-reclaim-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let targets = ["first", "second"].map { root.appendingPathComponent($0).path }
        for target in targets {
            try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
        }
        let keepGoing = root.appendingPathComponent("keep-going").path
        if !stopped { FileManager.default.createFile(atPath: keepGoing, contents: nil) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", SystemReclaimer.script(for: targets)]
        process.environment = [PrivilegedRunner.keepGoingVariable: keepGoing]
        let stdout = Pipe()
        process.standardOutput = stdout
        try process.run()
        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "the batch script failed: \(output)")

        let records = try XCTUnwrap(PrivilegedRunner.decodePayload(output))
        let statuses = SystemReclaimer.parseStatuses(records)
        let named = Dictionary(uniqueKeysWithValues: statuses.map {
            (URL(fileURLWithPath: $0.key).lastPathComponent, $0.value)
        })
        return (named, targets.filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0).lastPathComponent })
    }

    func testAStoppedBatchDeletesNothingFurther() throws {
        let result = try runScript(stopped: true)
        XCTAssertEqual(result.left, ["first", "second"], "nothing may be deleted once the run is stopped")
        XCTAssertEqual(result.statuses, ["first": "STOP", "second": "STOP"])
    }

    func testABatchThatIsNotStoppedDeletesEveryPath() throws {
        let result = try runScript(stopped: false)
        XCTAssertEqual(result.left, [])
        XCTAssertEqual(result.statuses, ["first": "OK", "second": "OK"])
    }

    func testItemsSkippedByAStopAreNotReportedAsReclaimed() async {
        let items = [systemItem(logsChild), systemItem(cachesChild)]
        let outcomes = await SystemReclaimer.reclaim(items, runner: { _ in
            self.payload([("OK", self.logsChild), ("STOP", self.cachesChild)])
        })
        XCTAssertNil(outcomes.first { $0.item.path == self.logsChild }?.failure)
        XCTAssertEqual(outcomes.first { $0.item.path == self.cachesChild }?.failure,
                       "stopped before this item was reached")
    }

    func testScriptQuotesHostileNames() {
        let hostile = "/private/var/root/Library/Logs/we'ird $(name)"
        let script = SystemReclaimer.script(for: [hostile])
        XCTAssertTrue(script.contains("'/private/var/root/Library/Logs/we'\\''ird $(name)'"),
                      "a quote in the name must not break out of the shell word")
        XCTAssertFalse(script.contains("rm -rf -- /private"),
                       "the path must never appear unquoted after rm")
    }

    func testParseStatusesMapsPathsToVerdicts() throws {
        let data = try XCTUnwrap(PrivilegedRunner.decodePayload(
            payload([("OK", logsChild), ("GONE", cachesChild), ("garbage", "")])))
        let statuses = SystemReclaimer.parseStatuses(data)
        XCTAssertEqual(statuses[logsChild], "OK")
        XCTAssertEqual(statuses[cachesChild], "GONE")
        XCTAssertEqual(statuses.count, 3, "even odd records parse as status/path pairs")
    }

    func testReclaimReportsPerItemVerdicts() async {
        let items = [systemItem(logsChild), systemItem(cachesChild)]
        let outcomes = await SystemReclaimer.reclaim(items, runner: { _ in
            self.payload([("OK", self.logsChild), ("ERR", self.cachesChild)])
        })
        XCTAssertNil(outcomes.first { $0.item.path == self.logsChild }?.failure)
        XCTAssertNotNil(outcomes.first { $0.item.path == self.cachesChild }?.failure)
    }

    func testReclaimFailsItemsTheHelperNeverReported() async {
        let outcomes = await SystemReclaimer.reclaim([systemItem(logsChild)],
                                                     runner: { _ in self.payload([]) })
        XCTAssertNotNil(outcomes.first?.failure,
                        "a missing verdict fails safe, never counts as reclaimed")
    }

    func testValidationFailuresNeverReachTheScript() async {
        let bad = systemItem("/private/var/root/Library/Logs/RTCReporting/deep")
        let good = systemItem(logsChild)
        let outcomes = await SystemReclaimer.reclaim([bad, good], runner: { script in
            XCTAssertFalse(script.contains("deep"),
                           "an invalid path must never be built into the privileged script")
            XCTAssertTrue(script.contains(self.logsChild),
                          "the valid path in the same batch still runs")
            return self.payload([("OK", self.logsChild)])
        })
        XCTAssertNotNil(outcomes.first { $0.item.path == bad.path }?.failure)
        XCTAssertNil(outcomes.first { $0.item.path == good.path }?.failure)
    }

    func testNonSystemItemsAreRefusedWithoutRunningAnything() async {
        let impostor = CleanableItem(label: "impostor", kind: .systemLogs,
                                     path: logsChild, anchorPaths: [],
                                     isKnownCache: true)   // isSystemArea stays false
        let outcomes = await SystemReclaimer.reclaim([impostor], runner: { _ in
            XCTFail("no privileged script may run for a batch with nothing valid")
            return ""
        })
        XCTAssertNotNil(outcomes.first?.failure)
    }

    func testCancelledAuthorizationFailsTheWholeBatchGracefully() async {
        let items = [systemItem(logsChild), systemItem(cachesChild)]
        let outcomes = await SystemReclaimer.reclaim(items, runner: { _ in
            throw PrivilegedRunner.Failure.cancelled
        })
        XCTAssertEqual(outcomes.count, 2)
        XCTAssertTrue(outcomes.allSatisfy {
            $0.failure?.contains("cancelled") ?? false
        })
    }
}
