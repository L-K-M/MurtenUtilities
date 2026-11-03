import XCTest
import MurtenCore
@testable import ShortkingCore

/// The pure half of the suite's watch: which conflicts count, how they are
/// identified, and what the suggestion says.
final class ShortcutConflictWatchTests: XCTestCase {

    private let commandShiftSpace = KeyCombo(keyCode: 0x31, modifiers: [.command, .shift])
    private let observedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func claim(_ name: String, _ bundleID: String?, layer: ClaimLayer,
                       kind: OwnerKind = .application, label: String? = nil,
                       combo: KeyCombo? = nil) -> Claim {
        Claim(
            combo: combo ?? commandShiftSpace,
            layer: layer,
            status: .known,
            owner: Owner(name: name, bundleID: bundleID, kind: kind),
            label: label
        )
    }

    private func conflict(_ claims: [Claim]) -> Conflict? {
        ConflictAnalyzer.conflict(for: ComboGroup(combo: claims[0].combo, claims: claims))
    }

    private var raycast: Claim { claim("Raycast", "com.raycast.macos", layer: .windowServer) }
    private var alfred: Claim { claim("Alfred", "com.runningwithcrayons.Alfred", layer: .windowServer) }

    // MARK: - Which conflicts count

    func testTwoAppsAtOneLayerAreBetweenApps() throws {
        let found = try XCTUnwrap(conflict([raycast, alfred]))
        XCTAssertEqual(found.kind, .definite)
        XCTAssertTrue(found.isBetweenApps)
    }

    func testShadowingIsBetweenApps() throws {
        let karabiner = claim("Karabiner-Elements", "org.pqrs.Karabiner", layer: .virtualHID, kind: .configTool)
        let found = try XCTUnwrap(conflict([karabiner, raycast]))
        XCTAssertEqual(found.kind, .shadowed)
        XCTAssertTrue(found.isBetweenApps)
    }

    func testMenuItemsShadowedOnlyInOneAppAreNot() throws {
        let menu = claim("Finder", "com.apple.finder", layer: .appMenu, label: "Get Info")
        let found = try XCTUnwrap(conflict([raycast, menu]))
        XCTAssertEqual(found.kind, .contextual)
        XCTAssertFalse(found.isBetweenApps)
    }

    func testMacOSDefaultsCollidingAreNot() throws {
        let first = claim("Mission Control", "com.apple.symbolichotkeys", layer: .symbolic, kind: .system,
                          label: "Move left a space")
        let second = claim("Mission Control", "com.apple.symbolichotkeys", layer: .symbolic, kind: .system,
                           label: "Switch to Desktop 1")
        let found = try XCTUnwrap(conflict([first, second]))
        XCTAssertTrue(found.isSystemDefault)
        XCTAssertFalse(found.isBetweenApps)
    }

    func testAnUnnamedClaimIsNot() throws {
        let probed = Claim(combo: commandShiftSpace, layer: .windowServer, status: .probedClaimed)
        let found = try XCTUnwrap(conflict([probed]))
        XCTAssertEqual(found.kind, .unattributed)
        XCTAssertFalse(found.isBetweenApps)
    }

    // MARK: - Acknowledgement identity

    func testSignatureIgnoresWhichAppsHappenedToBeRunning() throws {
        let karabiner = claim("Karabiner-Elements", "org.pqrs.Karabiner", layer: .virtualHID, kind: .configTool)
        let safariMenu = claim("Safari", "com.apple.Safari", layer: .appMenu, label: "Show Sidebar")

        let withMenu = try XCTUnwrap(conflict([karabiner, raycast, safariMenu]))
        let withoutMenu = try XCTUnwrap(conflict([karabiner, raycast]))

        XCTAssertEqual(withMenu.acknowledgementSignature, withoutMenu.acknowledgementSignature)
        XCTAssertEqual(withMenu.contenderNames, ["Karabiner-Elements", "Raycast"])
    }

    func testSignatureChangesWhenAnotherOwnerJoins() throws {
        let two = try XCTUnwrap(conflict([raycast, alfred]))
        let launchBar = claim("LaunchBar", "at.obdev.LaunchBar", layer: .windowServer)
        let three = try XCTUnwrap(conflict([raycast, alfred, launchBar]))

        XCTAssertNotEqual(two.acknowledgementSignature, three.acknowledgementSignature)
    }

    func testSignatureDoesNotDependOnOrder() throws {
        let one = try XCTUnwrap(conflict([raycast, alfred]))
        let other = try XCTUnwrap(conflict([alfred, raycast]))
        XCTAssertEqual(one.acknowledgementSignature, other.acknowledgementSignature)
        XCTAssertTrue(one.acknowledgementSignature.hasPrefix(commandShiftSpace.groupingKey + "#"))
    }

    func testDuplicateMenuItemsInOneAppAreTheirOwnContenders() throws {
        let first = claim("Preview", "com.apple.Preview", layer: .appMenu, label: "Rotate Left")
        let second = claim("Preview", "com.apple.Preview", layer: .appMenu, label: "Rotate Right")
        let found = try XCTUnwrap(conflict([first, second]))

        XCTAssertTrue(found.isBetweenApps)
        XCTAssertEqual(found.contenderNames, ["Preview"])
    }

    // MARK: - Findings

    func testOneFindingPerConflictBetweenApps() throws {
        let fight = try XCTUnwrap(conflict([raycast, alfred]))
        let other = KeyCombo(keyCode: 0x05, modifiers: [.command])
        let local = try XCTUnwrap(conflict([
            claim("Raycast", "com.raycast.macos", layer: .windowServer, combo: other),
            claim("Finder", "com.apple.finder", layer: .appMenu, label: "Go", combo: other),
        ]))

        let findings = ShortcutConflictFinding.findings(for: [fight, local], acknowledged: [], at: observedAt)

        XCTAssertEqual(findings.count, 1)
        let finding = try XCTUnwrap(findings.first)
        XCTAssertEqual(finding.moduleID, ShortkingSuite.moduleID)
        XCTAssertEqual(finding.condition, "conflict:" + commandShiftSpace.groupingKey)
        XCTAssertEqual(finding.scope, .local)
        XCTAssertEqual(finding.observedAt, observedAt)
        XCTAssertEqual(finding.text(ShortcutConflictFinding.EvidenceKey.combo), "⇧⌘Space")
        XCTAssertEqual(finding.text(ShortcutConflictFinding.EvidenceKey.contenders), "Raycast and Alfred")
        XCTAssertEqual(finding.count(ShortcutConflictFinding.EvidenceKey.contenderCount), 2)
        XCTAssertEqual(finding.count(ShortcutConflictFinding.EvidenceKey.acknowledged), 0)
    }

    func testAcknowledgedConflictIsMarked() throws {
        let fight = try XCTUnwrap(conflict([raycast, alfred]))
        let findings = ShortcutConflictFinding.findings(
            for: [fight], acknowledged: [fight.acknowledgementSignature], at: observedAt)

        XCTAssertEqual(findings.first?.count(ShortcutConflictFinding.EvidenceKey.acknowledged), 1)
    }

    // MARK: - Rule

    private func finding(for claims: [Claim], acknowledged: Bool = false) throws -> Finding {
        let found = try XCTUnwrap(conflict(claims))
        let signatures: Set<String> = acknowledged ? [found.acknowledgementSignature] : []
        return try XCTUnwrap(
            ShortcutConflictFinding.findings(for: [found], acknowledged: signatures, at: observedAt).first)
    }

    func testUnacknowledgedConflictSuggests() throws {
        let content = try XCTUnwrap(
            ShortcutConflictRule().suggestion(for: try finding(for: [raycast, alfred]), state: .inactive))

        XCTAssertEqual(content.title, "⇧⌘Space is claimed by two apps")
        XCTAssertTrue(content.detail.hasPrefix("Raycast and Alfred both claim ⇧⌘Space"))
        XCTAssertEqual(content.route, ShortkingSuite.conflictRoute(comboKey: commandShiftSpace.groupingKey))
    }

    func testAcknowledgedConflictDoesNotSuggest() throws {
        let acknowledged = try finding(for: [raycast, alfred], acknowledged: true)
        XCTAssertNil(ShortcutConflictRule().suggestion(for: acknowledged, state: .active))
    }

    func testThreeAppsAreCounted() throws {
        let launchBar = claim("LaunchBar", "at.obdev.LaunchBar", layer: .windowServer)
        let content = try XCTUnwrap(
            ShortcutConflictRule().suggestion(for: try finding(for: [raycast, alfred, launchBar]), state: .inactive))

        XCTAssertEqual(content.title, "⇧⌘Space is claimed by three apps")
        XCTAssertTrue(content.detail.hasPrefix("Raycast, Alfred and LaunchBar all claim"))
    }

    func testOneAppBindingTwiceIsWordedForOneApp() throws {
        let first = claim("Preview", "com.apple.Preview", layer: .appMenu, label: "Rotate Left")
        let second = claim("Preview", "com.apple.Preview", layer: .appMenu, label: "Rotate Right")
        let content = try XCTUnwrap(
            ShortcutConflictRule().suggestion(for: try finding(for: [first, second]), state: .inactive))

        XCTAssertEqual(content.title, "⇧⌘Space is claimed more than once by Preview")
        XCTAssertTrue(content.detail.hasPrefix("Preview binds ⇧⌘Space to more than one command"))
    }

    func testOtherConditionsAreIgnored() {
        let foreign = Finding(moduleID: ShortkingSuite.moduleID, condition: "something-else", observedAt: observedAt,
                              evidence: [ShortcutConflictFinding.EvidenceKey.combo: .text("⌘X"),
                                         ShortcutConflictFinding.EvidenceKey.comboKey: .text("k7|m1")])
        XCTAssertNil(ShortcutConflictRule().suggestion(for: foreign, state: .inactive))
    }

    func testSpelledOutCounts() {
        XCTAssertEqual(ShortcutConflictRule.spelledOut(2), "two")
        XCTAssertEqual(ShortcutConflictRule.spelledOut(10), "ten")
        XCTAssertEqual(ShortcutConflictRule.spelledOut(11), "11")
    }

    // MARK: - Route

    func testConflictRoutePassesTheAllowlist() throws {
        let allowlist = RouteAllowlist(modules: [ShortkingSuite.moduleID],
                                       actions: [ShortkingSuite.moduleID: ShortkingSuite.routeActions])
        let route = ShortkingSuite.conflictRoute(comboKey: commandShiftSpace.groupingKey)

        XCTAssertEqual(try allowlist.validate(route), route)
        XCTAssertEqual(try allowlist.route(from: route.url), route)
    }
}
