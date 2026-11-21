import XCTest
@testable import ShortkingKit
import ShortkingCore
@testable import ShortkingModule

@MainActor
final class ShortcutVerdictTests: XCTestCase {
    private let optionOne = KeyCombo(character: "1", modifiers: [.option])

    private func scan(
        outcome: CarbonHotKey.ProbeOutcome? = nil, owner: String? = nil, layer: ClaimLayer = .windowServer
    ) -> ScanResult {
        let report = outcome.map {
            ProbeReport(
                results: [.init(combo: optionOne, outcome: $0, status: $0 == .restricted ? CarbonHotKey.internalErr : 0)],
                breadth: .common, startedAt: Date(), finishedAt: Date(), probingVerified: true
            )
        }
        let claims = owner.map {
            [Claim(combo: optionOne, layer: layer, status: .known, owner: Owner(name: $0))]
        } ?? []
        return ScanResult(groups: ClaimMerger.group(claims), probeReport: report)
    }

    func testConfiguredOptionShortcutIsVisibleWithNoProbeOrAnAcceptedRegistration() {
        for outcome: CarbonHotKey.ProbeOutcome? in [nil, .accepted] {
            let verdict = AppState.verdict(for: optionOne, in: scan(outcome: outcome, owner: "Deskflow"))
            XCTAssertEqual(verdict.tone, .good)
            XCTAssertTrue(verdict.headline.contains("Deskflow"))
        }
        XCTAssertEqual(AppState.verdict(for: optionOne, in: scan()).tone, .unknown)
    }

    func testRefusedCarbonRegistrationPreservesAppMenuAndEventTapOwners() {
        for (owner, layer) in [("Finder", ClaimLayer.appMenu), ("skhd", .sessionTap), ("Deskflow", .windowServer)] {
            let verdict = AppState.verdict(for: optionOne, in: scan(outcome: .restricted, owner: owner, layer: layer))
            XCTAssertTrue((verdict.headline + verdict.detail).contains(owner))
            XCTAssertTrue(verdict.detail.contains("Carbon"))
        }
    }

    func testUnclaimedCombinationReportsOnlyAnObservedRestriction() {
        let scanResult = scan(outcome: .restricted)
        let verdict = AppState.verdict(for: optionOne, in: scanResult)
        XCTAssertEqual(verdict.tone, .blocked)
        XCTAssertTrue(verdict.detail.contains("Carbon"))
        XCTAssertTrue(verdict.offersInvestigation)
        let optionTwo = KeyCombo(character: "2", modifiers: [.option])
        XCTAssertEqual(AppState.verdict(for: optionTwo, in: scanResult).tone, .unknown)
    }
}
