import XCTest
import DoctorCore
import MurtenCore
@testable import DeviceControlDoctorModule

final class PermissionWatcherTests: XCTestCase {
    private var mac: FixtureMac!
    private var runner: FakeProcessRunner!
    private var watcher: PermissionWatcher!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        mac = try FixtureMac()
        runner = FakeProcessRunner()
        let now = self.now
        watcher = PermissionWatcher(watchList: mac.watchList, runner: runner, home: mac.home.path, now: { now })
    }

    override func tearDownWithError() throws {
        // Whatever a test observed, the watcher only looked.
        XCTAssertFalse(runner.ranReset, "the watcher must never reset a permission")
        mac.remove()
    }

    private func observeWithoutWriting() async throws -> WatchObservation {
        let before = try? Data(contentsOf: mac.watchList)
        let observation = await watcher.observe()
        XCTAssertEqual(try? Data(contentsOf: mac.watchList), before, "the watcher must never write the watch list")
        return observation
    }

    private func scope(_ app: WatchedApp) -> FindingScope { FindingScope(app.id.uuidString) }

    // MARK: - Cadence

    func testCadenceIsSlowLocalAndBounded() {
        XCTAssertGreaterThanOrEqual(watcher.cadence.interval, WatchCadence.minimumInterval)
        XCTAssertFalse(watcher.cadence.resources.contains(.network))
        XCTAssertEqual(watcher.moduleID, "devicecontroldoctor")
    }

    // MARK: - Permission records

    func testDeniedExpectedPermissionBecomesAVerifySuggestion() async throws {
        let app = try mac.installApp("PopChar", bundleID: "de.ergonis.PopChar", expecting: [.accessibility, .postEvent])
        try mac.saveWatchList([app])
        runner.offerListing()
        runner.report(.accessibility, for: app.bundleID, "denied", exitCode: 1)
        runner.report(.postEvent, for: app.bundleID, "granted", exitCode: 0)
        runner.sign(app.path)

        let observation = try await observeWithoutWriting()

        XCTAssertEqual(observation.outcome, .complete)
        XCTAssertEqual(observation.completedScopes, [scope(app)])
        let finding = try XCTUnwrap(observation.findings.first)
        XCTAssertEqual(observation.findings.count, 1)
        XCTAssertEqual(finding.scope, scope(app))
        let content = try XCTUnwrap(VerificationRule().suggestion(for: finding, state: .inactive))
        XCTAssertEqual(content.title, "Verify PopChar's permissions again")
        XCTAssertEqual(content.route, DoctorRoute.review(appID: app.id))
    }

    func testGrantedAndUnchangedAppIsCheckedAndClear() async throws {
        let app = try mac.installApp("Rocket", bundleID: "net.matthewpalmer.Rocket")
        try mac.saveWatchList([app])
        runner.offerListing()
        runner.report(.accessibility, for: app.bundleID, "granted", exitCode: 0)
        runner.sign(app.path)

        let observation = try await observeWithoutWriting()

        XCTAssertEqual(observation.outcome, .complete)
        XCTAssertEqual(observation.completedScopes, [scope(app)])
        XCTAssertTrue(observation.findings.isEmpty)
        XCTAssertEqual(runner.calls.filter { $0.dropFirst().first == "list" }.count, 1, "only expected services are queried")
    }

    func testUnavailableListingIsReportedUnavailableNeverHealthy() async throws {
        let app = try mac.installApp("Rocket", bundleID: "net.matthewpalmer.Rocket")
        try mac.saveWatchList([app])
        runner.withholdListing()
        runner.sign(app.path)

        let observation = try await observeWithoutWriting()

        XCTAssertEqual(observation.outcome, .unavailable)
        XCTAssertTrue(observation.completedScopes.isEmpty)
        XCTAssertTrue(observation.findings.isEmpty)
        XCTAssertEqual(observation.failures.map(\.kind), [.toolMissing])
        XCTAssertEqual(observation.failures.first?.scope, scope(app))
        XCTAssertFalse(runner.calls.contains { $0.dropFirst().first == "list" })
    }

    func testErrorsAndTimeoutsAreNotDenials() async throws {
        let unclear = try mac.installApp("One", bundleID: "com.example.One")
        let slow = try mac.installApp("Two", bundleID: "com.example.Two")
        try mac.saveWatchList([unclear, slow])
        runner.offerListing()
        runner.report(.accessibility, for: unclear.bundleID, "Error: query denied", exitCode: 1)
        runner.report(.accessibility, for: slow.bundleID, "", exitCode: 15, timedOut: true)
        runner.sign(unclear.path)
        runner.sign(slow.path)

        let observation = try await observeWithoutWriting()

        XCTAssertTrue(observation.findings.isEmpty)
        XCTAssertTrue(observation.completedScopes.isEmpty)
        XCTAssertEqual(Set(observation.failures.compactMap(\.scope)), [scope(unclear), scope(slow)])
        XCTAssertEqual(observation.outcome, .unavailable)
    }

    // MARK: - Signing identity

    func testChangedSigningIdentityIsReportedEvenWithoutListing() async throws {
        let app = try mac.installApp("Keyboard Maestro", bundleID: "com.stairways.keyboardmaestro.editor")
        try mac.saveWatchList([app])
        runner.withholdListing()
        runner.sign(app.path, team: "NEWTEAM999")

        let observation = try await observeWithoutWriting()

        XCTAssertEqual(observation.findings.map(\.scope), [scope(app)])
        XCTAssertEqual(observation.outcome, .partial, "the permission part still could not be read")
        let content = try XCTUnwrap(observation.findings.first.flatMap { VerificationRule().suggestion(for: $0, state: .inactive) })
        XCTAssertTrue(content.detail.contains("signing identity changed"), content.detail)
    }

    func testIdentityOnlyAppCompletesWithoutListing() async throws {
        let app = try mac.installApp("Helper", bundleID: "com.example.Helper", expecting: [])
        try mac.saveWatchList([app])
        runner.withholdListing()
        runner.sign(app.path)

        let observation = try await observeWithoutWriting()

        XCTAssertEqual(observation.outcome, .complete)
        XCTAssertEqual(observation.completedScopes, [scope(app)])
        XCTAssertFalse(runner.calls.contains { $0 == [SystemTool.tccutil] }, "no probe when no app needs it")
    }

    // MARK: - Apps the watcher cannot or may not read

    func testMissingAppAndReplacedBundleAreFailuresNotResolutions() async throws {
        let missing = try mac.installApp("Gone", bundleID: "com.example.Gone")
        let replaced = try mac.installApp("Swapped", bundleID: "com.example.Swapped")
        try FileManager.default.removeItem(atPath: missing.path)
        try mac.writeInfo(bundleID: "com.example.Other", name: "Swapped", at: URL(fileURLWithPath: replaced.path))
        try mac.saveWatchList([missing, replaced])

        let observation = try await observeWithoutWriting()

        XCTAssertTrue(observation.completedScopes.isEmpty)
        XCTAssertTrue(observation.findings.isEmpty)
        XCTAssertEqual(Set(observation.failures.compactMap(\.scope)), [scope(missing), scope(replaced)])
        XCTAssertTrue(runner.calls.isEmpty, "nothing is run against an app that is not there")
    }

    func testAppsInProtectedFoldersAreLeftToThePane() async throws {
        let guarded = try mac.installApp("Downloaded", bundleID: "com.example.Downloaded", in: "home/Downloads")
        try mac.saveWatchList([guarded])

        let observation = try await observeWithoutWriting()

        XCTAssertEqual(observation.failures.map(\.kind), [.permissionDenied])
        XCTAssertEqual(observation.failures.first?.scope, scope(guarded))
        XCTAssertTrue(runner.calls.isEmpty, "a protected folder is never read in the background")
    }

    // MARK: - The watch list

    func testMissingWatchListIsACompleteEmptyCheck() async throws {
        let observation = try await observeWithoutWriting()
        XCTAssertEqual(observation.outcome, .complete)
        XCTAssertTrue(observation.findings.isEmpty)
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testUnreadableWatchListIsUnavailable() async throws {
        try FileManager.default.createDirectory(at: mac.watchList.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"schemaVersion\": 2, \"apps\": [], \"events\": []}".utf8).write(to: mac.watchList)

        let observation = try await observeWithoutWriting()

        XCTAssertEqual(observation.outcome, .unavailable)
        XCTAssertEqual(observation.failures.first?.kind, .malformedResponse)
    }

    func testRemovedAppIsCheckedAndAbsent() async throws {
        let kept = try mac.installApp("Kept", bundleID: "com.example.Kept")
        let removed = try mac.installApp("Removed", bundleID: "com.example.Removed")
        runner.offerListing()
        for app in [kept, removed] {
            runner.report(.accessibility, for: app.bundleID, "denied", exitCode: 1)
            runner.sign(app.path)
        }
        try mac.saveWatchList([kept, removed])
        _ = try await observeWithoutWriting()

        try mac.saveWatchList([kept])
        let observation = try await observeWithoutWriting()

        XCTAssertTrue(observation.completedScopes.contains(scope(removed)))
        XCTAssertEqual(observation.findings.map(\.scope), [scope(kept)])
    }

    // MARK: - Cancellation

    func testCancellationStopsBeforeFurtherCommands() async throws {
        let first = try mac.installApp("First", bundleID: "com.example.First")
        let second = try mac.installApp("Second", bundleID: "com.example.Second")
        try mac.saveWatchList([first, second])
        runner.offerListing()
        runner.cancelCallingTask()

        let watcher = self.watcher!
        let observation = await Task { await watcher.observe() }.value

        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(observation.outcome, .unavailable)
        XCTAssertTrue(observation.findings.isEmpty)
    }
}
