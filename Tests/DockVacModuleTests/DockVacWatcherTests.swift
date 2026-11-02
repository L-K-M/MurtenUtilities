import DockVacCore
import DockVacDocker
import Foundation
import MurtenCore
import XCTest

@testable import DockVacModule

#if canImport(Glibc)
  import Glibc
#elseif canImport(Musl)
  import Musl
#elseif canImport(Darwin)
  import Darwin
#endif

/// The watcher against fixture data: what it reports, for which scope, and how it fails.
final class DockVacWatcherTests: XCTestCase {
  private static let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
  private static let socket = "/Users/test/.docker/run/docker.sock"

  private func watcher(_ reader: some DockerUsageReading) -> DockVacWatcher {
    DockVacWatcher(reader: reader, now: { Self.observedAt })
  }

  // MARK: - Observations

  func testReportsTheSafeLevelsBytesForTheEndpointItReached() async throws {
    let usage = try ModuleFixtures.diskUsage()
    let observation = await watcher(FixedReader(.success(.init(endpointAddress: Self.socket, usage: usage))))
      .observe()

    XCTAssertEqual(observation.outcome, .complete)
    XCTAssertEqual(observation.moduleID, DockVacSuite.moduleID)
    XCTAssertEqual(observation.completedScopes, [FindingScope(Self.socket)])
    let finding = try XCTUnwrap(observation.findings.first)
    XCTAssertEqual(observation.findings.count, 1)
    XCTAssertEqual(finding.condition, DockVacSuite.reclaimableCondition)
    XCTAssertEqual(finding.scope, FindingScope(Self.socket))
    XCTAssertEqual(finding.observedAt, Self.observedAt)

    let plan = UsageAnalyzer.analyze(usage).automaticCleanupPlan(.safe)
    XCTAssertEqual(finding.bytes(DockVacSuite.bytesEvidence), Int64(plan.estimatedReclaimableBytes))
    XCTAssertEqual(finding.count(DockVacSuite.itemsEvidence), plan.operations.count)
  }

  func testAFindingBelowTheThresholdStillCompletesTheScope() async {
    // "Checked and small" must resolve an earlier suggestion, so the scope completes
    // with a finding the rule then declines.
    let observation = await watcher(
      FixedReader(.success(.init(endpointAddress: Self.socket, usage: DockerDiskUsage())))
    ).observe()
    XCTAssertEqual(observation.outcome, .complete)
    XCTAssertEqual(observation.findings.first?.bytes(DockVacSuite.bytesEvidence), 0)
    XCTAssertNil(
      RebuildableSpaceRule().suggestion(for: observation.findings[0], state: .active))
  }

  func testFeedsARuleWhoseRouteReclaimsThatEndpoint() async throws {
    let large = DockerDiskUsage(buildCache: [
      BuildCacheRecord(
        id: "cache", type: "regular", recordDescription: "RUN make", inUse: false,
        shared: false, sizeBytes: 6_000_000_000, createdAt: nil, lastUsedAt: nil, usageCount: 1)
    ])
    let observation = await watcher(
      FixedReader(.success(.init(endpointAddress: Self.socket, usage: large)))
    ).observe()
    let content = try XCTUnwrap(
      RebuildableSpaceRule().suggestion(for: try XCTUnwrap(observation.findings.first), state: .inactive))
    XCTAssertEqual(content.title, "Docker is holding ~6 GB you can rebuild")
    XCTAssertEqual(content.route, DockVacSuite.reclaimRoute(endpoint: Self.socket))
  }

  // MARK: - Failures

  func testNoDaemonMakesTheWholeCheckUnavailable() async throws {
    let observation = await watcher(
      FixedReader(.failure(DockerEngineError.daemonNotFound(attempts: ["a: not present"], unsupported: []))))
      .observe()
    XCTAssertEqual(observation.outcome, .unavailable)
    XCTAssertTrue(observation.findings.isEmpty)
    XCTAssertTrue(observation.completedScopes.isEmpty)
    let failure = try XCTUnwrap(observation.failures.first)
    XCTAssertEqual(failure.kind, .unreachable)
    XCTAssertNil(failure.scope, "no endpoint answered, so no scope can be blamed")
    XCTAssertEqual(failure.message, "Docker does not seem to be running.")
  }

  func testAReadFailingAfterConnectingIsScopedToThatEndpoint() async throws {
    let observation = await watcher(
      FixedReader(.failure(DockerUsageReadFailure(
        endpointAddress: Self.socket, underlying: DockerEngineError.timedOut(path: Self.socket)))))
      .observe()
    XCTAssertEqual(observation.outcome, .unavailable)
    XCTAssertTrue(observation.completedScopes.isEmpty, "a failed read never proves resolution")
    let failure = try XCTUnwrap(observation.failures.first)
    XCTAssertEqual(failure.kind, .timedOut)
    XCTAssertEqual(failure.scope, FindingScope(Self.socket))
  }

  func testFailureKinds() {
    let scope = FindingScope("ssh://build-box")
    func kind(_ error: any Error) -> ObservationFailure.Kind {
      DockVacWatcher.failure(error, scope: scope).kind
    }
    XCTAssertEqual(
      kind(DockerEngineError.sshUnavailable(host: "ssh://build-box", detail: "Permission denied (publickey).")),
      .permissionDenied)
    XCTAssertEqual(
      kind(DockerEngineError.sshUnavailable(host: "ssh://build-box", detail: "Connection refused")),
      .unreachable)
    XCTAssertEqual(
      kind(DockerEngineError.socketUnavailable(path: Self.socket, detail: "Permission denied")),
      .permissionDenied)
    XCTAssertEqual(kind(DockerEngineError.malformedResponse("junk")), .malformedResponse)
    XCTAssertEqual(kind(DockerEngineError.api(status: 500, message: "boom")), .failed)
    XCTAssertEqual(kind(DockerSSHHostError.invalidAddress), .failed)
    XCTAssertEqual(
      DockVacWatcher.failure(
        DockerEngineError.sshUnavailable(host: "ssh://build-box", detail: "x"), scope: scope
      ).message,
      "Could not connect to Docker at ssh://build-box over SSH.",
      "the first line of DockVac's own message")
  }

  func testCancellationIsAFailureNotAResolution() async {
    let reader = BlockingReader()
    let watcher = watcher(reader)
    let task = Task { await watcher.observe() }
    await reader.waitUntilReading()
    task.cancel()
    let observation = await task.value
    XCTAssertTrue(observation.findings.isEmpty)
    XCTAssertTrue(observation.completedScopes.isEmpty)
    XCTAssertEqual(observation.failures.count, 1)
  }

  // MARK: - Cadence

  func testHourlyCadenceDeclaresNetworkOnlyForRemoteEndpoints() {
    let local = watcher(FixedReader(.success(.init(endpointAddress: Self.socket, usage: .empty))))
    XCTAssertEqual(local.cadence.interval, 3600)
    XCTAssertGreaterThanOrEqual(local.cadence.interval, WatchCadence.minimumInterval)
    XCTAssertEqual(local.cadence.timeout, 180)
    XCTAssertFalse(local.cadence.resources.contains(.network))

    var remote = FixedReader(.success(.init(endpointAddress: "ssh://build-box", usage: .empty)))
    remote.readsRemoteEndpoint = true
    XCTAssertTrue(watcher(remote).cadence.resources.contains(.network))
  }

  func testLiveReaderDeclaresNetworkOnlyForAnAllowedSSHHost() {
    func reader(_ environment: [String: String], allowsSSH: Bool) -> LiveDockerUsageReader {
      Self.liveReader(environment, allowsSSH: allowsSSH)
    }
    let ssh = ["DOCKER_HOST": "ssh://deploy@build-box"]
    XCTAssertTrue(reader(ssh, allowsSSH: true).readsRemoteEndpoint)
    XCTAssertFalse(
      reader(ssh, allowsSSH: false).readsRemoteEndpoint, "a skipped host uses no network")
    XCTAssertFalse(
      reader(["DOCKER_HOST": "unix:///var/run/docker.sock"], allowsSSH: true).readsRemoteEndpoint)
    XCTAssertFalse(reader([:], allowsSSH: true).readsRemoteEndpoint)
  }

  // MARK: - SSH endpoints

  func testSSHEndpointIsSkippedUnlessTheUserAllowsIt() async throws {
    let started = Date()
    let reader = Self.liveReader(["DOCKER_HOST": "ssh://deploy@build-box:2222"], allowsSSH: false)
    let observation = await DockVacWatcher(reader: reader).observe()

    XCTAssertLessThan(Date().timeIntervalSince(started), 1, "nothing was dialled")
    XCTAssertEqual(observation.outcome, .unavailable)
    XCTAssertTrue(observation.findings.isEmpty)
    XCTAssertTrue(observation.completedScopes.isEmpty, "skipping never proves resolution")
    let failure = try XCTUnwrap(observation.failures.first)
    XCTAssertEqual(failure.kind, .permissionDenied)
    XCTAssertEqual(failure.scope, FindingScope("ssh://deploy@build-box:2222"))
    XCTAssertEqual(failure.message, "SSH endpoints are checked when you open DockVac.")
  }

  func testASkippedSSHEndpointKeepsItsSuggestionStale() async throws {
    let host = "ssh://deploy@build-box"
    let store = SuggestionStore(
      persistence: NoPersistence(), knownModules: [DockVacSuite.moduleID])
    let rule = RebuildableSpaceRule()
    let found = Finding(
      moduleID: DockVacSuite.moduleID, condition: DockVacSuite.reclaimableCondition,
      scope: FindingScope(host), observedAt: Self.observedAt,
      evidence: [DockVacSuite.bytesEvidence: .bytes(6_000_000_000)])
    _ = await store.record(
      .complete(
        moduleID: DockVacSuite.moduleID, at: Self.observedAt, scopes: [FindingScope(host)],
        findings: [found]),
      rule: rule, at: Self.observedAt)

    let later = Self.observedAt.addingTimeInterval(3600)
    let skipped = await DockVacWatcher(
      reader: Self.liveReader(["DOCKER_HOST": host], allowsSSH: false), now: { later }
    ).observe()
    _ = await store.record(skipped, rule: rule, at: later)

    let suggestions = await store.suggestions(at: later)
    XCTAssertEqual(suggestions.count, 1, "the suggestion survives the skipped check")
    guard case .stale? = suggestions.first?.freshness else {
      return XCTFail("a skipped check marks it stale: \(String(describing: suggestions.first))")
    }
  }

  func testTheSSHPreferenceIsOffByDefault() throws {
    let suite = "DockVacWatcherTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preference = SSHBackgroundPreference(defaults: defaults)
    XCTAssertFalse(preference.isOn)
    defaults.set(true, forKey: SSHBackgroundPreference.key)
    XCTAssertTrue(preference.isOn)
  }

  private static func liveReader(_ environment: [String: String], allowsSSH: Bool)
    -> LiveDockerUsageReader
  {
    LiveDockerUsageReader(
      locator: DockerEndpointLocator(
        environment: environment,
        homeDirectory: NSTemporaryDirectory() + "dockvac-nohome-\(UUID().uuidString)"),
      readTimeout: 5, allowsSSH: { allowsSSH })
  }
}

// MARK: - The live reader against the fixture daemon

/// Runs the real reader against Tests/DockVacDockerTests/Scripts/fake-docker.py, which
/// replays the captured fixtures and logs every request. Proves the watcher only reads.
final class LiveDockerUsageReaderTests: XCTestCase {
  private var process: Process?
  private var socketPath = ""
  private var requestLogPath = ""

  override func setUp() async throws {
    try await super.setUp()
    let python = ["/usr/bin/python3", "/usr/local/bin/python3", "/opt/homebrew/bin/python3"]
      .first { FileManager.default.isExecutableFile(atPath: $0) }
    guard let python else {
      throw XCTSkip("python3 is not available")
    }
    let script = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("DockVacDockerTests/Scripts/fake-docker.py")
    guard FileManager.default.fileExists(atPath: script.path) else {
      throw XCTSkip("fake-docker.py not found at \(script.path)")
    }
    let token = UUID().uuidString.prefix(8)
    socketPath = NSTemporaryDirectory() + "dockvac-watch-\(token).sock"
    requestLogPath = NSTemporaryDirectory() + "dockvac-watch-\(token).log"

    let process = Process()
    process.executableURL = URL(fileURLWithPath: python)
    process.arguments = [script.path, "--socket", socketPath, "--request-log", requestLogPath]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    self.process = process

    let deadline = Date().addingTimeInterval(10)
    while !FileManager.default.fileExists(atPath: socketPath) {
      guard Date() < deadline, process.isRunning else {
        throw XCTSkip("fake daemon did not start")
      }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
  }

  override func tearDown() async throws {
    if let process, process.isRunning {
      process.terminate()
      let deadline = Date().addingTimeInterval(2)
      while process.isRunning, Date() < deadline {
        try await Task.sleep(nanoseconds: 50_000_000)
      }
      if process.isRunning {
        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
      }
    }
    process = nil
    try? FileManager.default.removeItem(atPath: socketPath)
    try? FileManager.default.removeItem(atPath: requestLogPath)
    try await super.tearDown()
  }

  func testReadsOnlyAndSkipsVolumes() async throws {
    let reader = LiveDockerUsageReader(
      locator: DockerEndpointLocator(
        environment: ["DOCKER_HOST": "unix://\(socketPath)"],
        homeDirectory: NSTemporaryDirectory() + "dockvac-nohome", probeTimeout: 10),
      readTimeout: 10, allowsSSH: { false })
    let observation = await DockVacWatcher(reader: reader).observe()

    XCTAssertEqual(observation.outcome, .complete, "\(observation.failures)")
    XCTAssertEqual(observation.completedScopes, [FindingScope(socketPath)])
    let bytes = try XCTUnwrap(observation.findings.first?.bytes(DockVacSuite.bytesEvidence))
    let fixture = UsageAnalyzer.analyze(try ModuleFixtures.diskUsage()).automaticCleanupPlan(.safe)
    XCTAssertEqual(bytes, Int64(fixture.estimatedReclaimableBytes))

    let text = try String(contentsOfFile: requestLogPath, encoding: .utf8)
    let requests = text.split(separator: "\n").map(String.init)
    XCTAssertFalse(requests.isEmpty)
    for request in requests {
      XCTAssertTrue(request.hasPrefix("GET "), "the watcher only reads: \(request)")
    }
    XCTAssertFalse(
      requests.contains { $0.contains("type=volume") || $0.hasSuffix("/system/df") },
      "volume sizes are never asked for: \(requests)")
  }
}

// MARK: - Fakes

private struct NoPersistence: SuggestionPersisting {
  func load() throws -> SuggestionLedger? { nil }
  func save(_ ledger: SuggestionLedger) throws {}
  func quarantine() throws -> URL? { nil }
}

private struct FixedReader: DockerUsageReading {
  let result: Result<DockerUsageSnapshot, any Error>
  var readsRemoteEndpoint = false

  init(_ result: Result<DockerUsageSnapshot, any Error>) {
    self.result = result
  }

  func readUsage() async throws -> DockerUsageSnapshot {
    try result.get()
  }
}

/// Reads until cancelled, the way a slow daemon looks to the watcher.
private final class BlockingReader: DockerUsageReading, @unchecked Sendable {
  private let lock = NSLock()
  private var reading = false
  let readsRemoteEndpoint = false

  func readUsage() async throws -> DockerUsageSnapshot {
    lock.withLock { reading = true }
    while true {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
  }

  func waitUntilReading() async {
    while !lock.withLock({ reading }) {
      try? await Task.sleep(nanoseconds: 5_000_000)
    }
  }
}

/// The fixtures DockVacCoreTests keeps, read from the source tree: a test target cannot
/// reach another's resource bundle.
enum ModuleFixtures {
  static func diskUsage() throws -> DockerDiskUsage {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("DockVacCoreTests/Fixtures/system_df.json")
    return try DockerEngineDecoder.decodeDiskUsage(Data(contentsOf: url))
  }
}
