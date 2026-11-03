import XCTest
import MurtenCore
import ShortkingCore
import ShortkingKit
@testable import ShortkingModule

/// A fixed view of "this Mac" for the watcher. Never the live system.
private final class FixtureInventory: ShortcutInventoryObserving, @unchecked Sendable {
    enum Saved {
        case claims([Claim])
        case missing
        case error(Error)
    }

    private let lock = NSLock()
    private let saved: Saved
    private let system: [Claim]
    private let acknowledged: Set<String>
    private var systemReads = 0

    init(saved: Saved, system: [Claim] = [], acknowledged: Set<String> = []) {
        self.saved = saved
        self.system = system
        self.acknowledged = acknowledged
    }

    var systemReadCount: Int {
        lock.withLock { systemReads }
    }

    func savedInventory() throws -> [Claim]? {
        switch saved {
        case .claims(let claims): return claims
        case .missing: return nil
        case .error(let error): throw error
        }
    }

    func currentSystemShortcuts() async -> [Claim] {
        lock.withLock { systemReads += 1 }
        return system
    }

    func acknowledgedConflicts() -> Set<String> { acknowledged }
}

final class ShortkingWatcherTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let commandSpace = KeyCombo(keyCode: 0x31, modifiers: [.command])
    private let optionSpace = KeyCombo(keyCode: 0x31, modifiers: [.option, .command])

    private func app(_ name: String, _ bundleID: String, on combo: KeyCombo) -> Claim {
        Claim(combo: combo, layer: .windowServer, status: .known,
              owner: Owner(name: name, bundleID: bundleID), label: "Toggle")
    }

    /// Spotlight's search hotkey, as the symbolic scanner reports it.
    private func spotlight(on combo: KeyCombo) -> Claim {
        Claim(combo: combo, layer: .symbolic, status: .known,
              owner: SymbolicHotKeyCatalog.owner(for: 64), label: SymbolicHotKeyCatalog.label(for: 64))
    }

    private var raycast: Claim { app("Raycast", "com.raycast.macos", on: commandSpace) }
    private var alfred: Claim { app("Alfred", "com.runningwithcrayons.Alfred", on: commandSpace) }

    private func watcher(_ inventory: FixtureInventory) -> ShortkingWatcher {
        let now = self.now
        return ShortkingWatcher(inventory: inventory, now: { now })
    }

    // MARK: - Cadence

    func testCadenceIsRareAndLocal() {
        let cadence = watcher(FixtureInventory(saved: .missing)).cadence
        XCTAssertGreaterThanOrEqual(cadence.interval, WatchCadence.minimumInterval)
        XCTAssertFalse(cadence.resources.contains(.network))
    }

    // MARK: - Failures are failures

    func testNoInventoryYetIsUnavailable() async {
        let observation = await watcher(FixtureInventory(saved: .missing)).observe()

        XCTAssertEqual(observation.outcome, .unavailable)
        XCTAssertEqual(observation.failures.first?.kind, .toolMissing)
        XCTAssertTrue(observation.completedScopes.isEmpty)
    }

    func testUnreadableInventoryIsMalformed() async {
        let observation = await watcher(
            FixtureInventory(saved: .error(StoreFileReader.ReadError.malformed))).observe()

        XCTAssertEqual(observation.outcome, .unavailable)
        XCTAssertEqual(observation.failures.first?.kind, .malformedResponse)
    }

    func testNewerInventoryIsMalformed() async {
        let observation = await watcher(
            FixtureInventory(saved: .error(StoreFileReader.ReadError.newerSchema(2)))).observe()

        XCTAssertEqual(observation.failures.first?.kind, .malformedResponse)
        XCTAssertTrue(observation.failures.first?.message.contains("newer") ?? false)
    }

    func testOtherReadErrorsFail() async {
        let observation = await watcher(
            FixtureInventory(saved: .error(CocoaError(.fileReadNoPermission)))).observe()

        XCTAssertEqual(observation.outcome, .unavailable)
        XCTAssertEqual(observation.failures.first?.kind, .failed)
    }

    func testACancelledCheckReportsNothing() async {
        let watcher = self.watcher(FixtureInventory(saved: .claims([raycast, alfred])))
        let observation = await Task { () -> WatchObservation in
            withUnsafeCurrentTask { $0?.cancel() }
            return await watcher.observe()
        }.value

        XCTAssertTrue(observation.findings.isEmpty)
        XCTAssertTrue(observation.completedScopes.isEmpty)
        XCTAssertFalse(observation.failures.isEmpty)
    }

    // MARK: - Findings

    func testConflictBetweenAppsIsFound() async throws {
        let observation = await watcher(FixtureInventory(saved: .claims([raycast, alfred]))).observe()

        XCTAssertEqual(observation.outcome, .complete)
        XCTAssertEqual(observation.completedScopes, [.local])
        XCTAssertEqual(observation.observedAt, now)
        let finding = try XCTUnwrap(observation.findings.first)
        XCTAssertEqual(observation.findings.count, 1)
        XCTAssertEqual(finding.condition, ShortcutConflictFinding.condition(comboKey: commandSpace.groupingKey))
        XCTAssertEqual(finding.count(ShortcutConflictFinding.EvidenceKey.acknowledged), 0)
    }

    func testInventoryWithoutSystemShortcutsIsNotRefreshed() async {
        let inventory = FixtureInventory(saved: .claims([raycast, alfred]), system: [spotlight(on: commandSpace)])
        let observation = await watcher(inventory).observe()

        XCTAssertEqual(inventory.systemReadCount, 0, "a scan without system shortcuts does not get them here")
        XCTAssertEqual(observation.findings.count, 1)
    }

    func testFreshSystemShortcutsReplaceTheSavedOnes() async {
        // Saved: Spotlight and Raycast both on ⌘Space. Since then the user moved
        // Spotlight to ⌥⌘Space in System Settings.
        let inventory = FixtureInventory(saved: .claims([spotlight(on: commandSpace), raycast]),
                                         system: [spotlight(on: optionSpace)])
        let observation = await watcher(inventory).observe()

        XCTAssertEqual(inventory.systemReadCount, 1)
        XCTAssertEqual(observation.outcome, .complete)
        XCTAssertTrue(observation.findings.isEmpty, "checked and absent resolves the old suggestion")
        XCTAssertEqual(observation.completedScopes, [.local])
    }

    func testFreshSystemShortcutsCanCreateAConflict() async {
        let inventory = FixtureInventory(saved: .claims([spotlight(on: optionSpace), raycast]),
                                         system: [spotlight(on: commandSpace)])
        let observation = await watcher(inventory).observe()

        XCTAssertEqual(observation.findings.map(\.condition),
                       [ShortcutConflictFinding.condition(comboKey: commandSpace.groupingKey)])
    }

    func testUnreadableSystemShortcutsKeepTheInventoryButProveNothing() async {
        let inventory = FixtureInventory(saved: .claims([spotlight(on: commandSpace), raycast]), system: [])
        let observation = await watcher(inventory).observe()

        XCTAssertEqual(observation.outcome, .partial)
        XCTAssertEqual(observation.findings.count, 1, "the saved conflict still stands")
        XCTAssertTrue(observation.completedScopes.isEmpty, "nothing may resolve")
        XCTAssertEqual(observation.failures.first?.kind, .failed)
    }

    // MARK: - Through the ledger

    func testAcknowledgingResolvesTheSuggestion() async throws {
        var ledger = SuggestionLedger()
        let rule = ShortcutConflictRule()

        let first = await watcher(FixtureInventory(saved: .claims([raycast, alfred]))).observe()
        ledger.apply(first, rule: rule)
        let suggestion = try XCTUnwrap(ledger.suggestions(at: now).first)
        XCTAssertEqual(suggestion.title, "⌘Space is claimed by two apps")
        XCTAssertEqual(suggestion.route, ShortkingSuite.conflictRoute(comboKey: commandSpace.groupingKey))

        let signature = try XCTUnwrap(ShortcutInventory.conflicts(in: [raycast, alfred]).first)
            .acknowledgementSignature
        let acknowledged = await watcher(
            FixtureInventory(saved: .claims([raycast, alfred]), acknowledged: [signature])).observe()
        let events = ledger.apply(acknowledged, rule: rule)

        XCTAssertTrue(ledger.suggestions(at: now).isEmpty)
        XCTAssertEqual(events, [.resolved(suggestion.key)])
    }

    func testAThirdAppReopensAnAcknowledgedConflict() async throws {
        let rule = ShortcutConflictRule()
        let signature = try XCTUnwrap(ShortcutInventory.conflicts(in: [raycast, alfred]).first)
            .acknowledgementSignature
        let launchBar = app("LaunchBar", "at.obdev.LaunchBar", on: commandSpace)

        var ledger = SuggestionLedger()
        let observation = await watcher(
            FixtureInventory(saved: .claims([raycast, alfred, launchBar]), acknowledged: [signature])).observe()
        ledger.apply(observation, rule: rule)

        XCTAssertEqual(ledger.suggestions(at: now).first?.title, "⌘Space is claimed by three apps")
    }
}
