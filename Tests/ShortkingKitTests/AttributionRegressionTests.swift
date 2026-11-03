import Foundation
import XCTest
import ShortkingCore
@testable import ShortkingKit

final class AttributionRegressionTests: XCTestCase {
    private let combo = KeyCombo(character: "g", modifiers: .command)
    private let other = KeyCombo(character: "h", modifiers: .command)
    private let at = Date(timeIntervalSince1970: 100)

    func testLiveCaptureRequiresMatchingPhysicalPress() {
        var correlation = LiveCaptureCorrelation()
        correlation.reset(target: combo)
        XCTAssertFalse(correlation.takeMatchingDelivery(at: at))
        correlation.recordPress(other, at: at)
        XCTAssertFalse(correlation.takeMatchingDelivery(at: at))
        correlation.recordPress(combo, at: at)
        XCTAssertTrue(correlation.takeMatchingDelivery(at: at.addingTimeInterval(0.01)))
        XCTAssertFalse(correlation.takeMatchingDelivery(at: at.addingTimeInterval(0.02)))
        correlation.recordPress(combo, at: at)
        XCTAssertFalse(correlation.takeMatchingDelivery(at: at.addingTimeInterval(1)))
        XCTAssertFalse(correlation.takeMatchingDelivery(at: at.addingTimeInterval(-0.01)))
        correlation.recordPress(other, at: at)
        XCTAssertFalse(correlation.takeMatchingDelivery(at: at))
    }

    func testTargetChangesAndStopDiscardQueuedDeliveries() {
        var correlation = LiveCaptureCorrelation()
        correlation.reset(target: combo)
        correlation.recordPress(combo, at: at)
        correlation.reset(target: other)
        XCTAssertFalse(correlation.takeMatchingDelivery(at: at))
        correlation.recordPress(other, at: at)
        correlation.reset()
        XCTAssertFalse(correlation.takeMatchingDelivery(at: at))
    }

    func testProcessCountIsNotByteCount() {
        let pids: [Int32] = [1, 2, 3, 4, 5, 6, 7, 8]
        let result = ProcessSampling.cpuTimes(pids: pids, reportedCount: 8) { UInt64($0) }
        XCTAssertEqual(result.count, pids.count)
        XCTAssertEqual(result[8], 8)
        XCTAssertEqual(ProcessSampling.cpuTimes(pids: pids, reportedCount: 100) { UInt64($0) }.count, 8)
        XCTAssertTrue(ProcessSampling.cpuTimes(pids: pids, reportedCount: -1) { UInt64($0) }.isEmpty)
        let missingSample = ProcessSampling.cpuTimes(pids: [0, -1, 3], reportedCount: 3) { _ in nil }
        XCTAssertTrue(missingSample.isEmpty)
    }

    func testMixedTransitionsRetainAmbiguityWithoutCrossAttribution() {
        let launched = Owner(name: "Launched", bundleID: "test.launch", kind: .application)
        let quit = Owner(name: "Quit", bundleID: "test.quit", kind: .application)
        let result = DifferentialObservations.build(candidates: [
            .init(owner: launched, direction: .launch, at: at),
            .init(owner: quit, direction: .termination, at: at)
        ], freed: [combo], newlyClaimed: [other])
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { !$0.ambiguous })
        XCTAssertEqual(result.first { $0.ownerIdentity == launched.identity }?.comboKey, other.groupingKey)
        XCTAssertEqual(result.first { $0.ownerIdentity == quit.identity }?.comboKey, combo.groupingKey)
    }

    func testSameDirectionTransitionsRemainAmbiguous() {
        let first = Owner(name: "First", bundleID: "test.first", kind: .application)
        let second = Owner(name: "Second", bundleID: "test.second", kind: .application)
        let result = DifferentialObservations.build(candidates: [
            .init(owner: first, direction: .launch, at: at),
            .init(owner: second, direction: .launch, at: at)
        ], freed: [], newlyClaimed: [combo])

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy(\.ambiguous))
    }

    func testDifferentialEvidenceMatchesTransitionDirection() {
        let owner = Owner(name: "App", bundleID: "test.app", kind: .application)
        for direction in [DifferentialObservations.Direction.launch, .termination] {
            let candidate = DifferentialObservations.Transition(owner: owner, direction: direction, at: at)
            let freed = DifferentialObservations.build(candidates: [candidate], freed: [combo], newlyClaimed: [])
            let claimed = DifferentialObservations.build(candidates: [candidate], freed: [], newlyClaimed: [combo])
            switch direction {
            case .launch:
                XCTAssertTrue(freed.isEmpty)
                XCTAssertEqual(claimed.map(\.kind), [.claimedOnLaunch])
            case .termination:
                XCTAssertEqual(freed.map(\.kind), [.freedOnQuit])
                XCTAssertTrue(claimed.isEmpty)
            }
        }
    }
}
