import Foundation
import XCTest
@testable import CoreographyCore

final class SustainedCPUTrackerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    func testAveragesCPUTimeOverAboutAnHourOfPolls() {
        var tracker = SustainedCPUTracker()
        // One core busy throughout: 900 s of CPU per 15-minute poll.
        for poll in 0...3 {
            let outcome = tracker.record([process("Xcode", cpuSeconds: Double(poll) * 900)], at: at(Double(poll) * 15))
            XCTAssertTrue(outcome.usage.isEmpty, "no full window yet at \(poll * 15) min")
            XCTAssertFalse(outcome.coversWindow)
        }

        let hour = tracker.record([process("Xcode", cpuSeconds: 3600)], at: at(60))
        XCTAssertTrue(hour.coversWindow)
        XCTAssertEqual(hour.usage.count, 1)
        XCTAssertEqual(hour.usage[0].span, 3600)
        XCTAssertEqual(hour.usage[0].averageCores, 1, accuracy: 0.001)

        // The baseline moves with the polls: the last hour, not since launch.
        let later = tracker.record([process("Xcode", cpuSeconds: 3600 + 90)], at: at(75))
        XCTAssertEqual(later.usage[0].span, 3600)
        XCTAssertEqual(later.usage[0].averageCores, (3690 - 900) / 3600, accuracy: 0.001)
    }

    func testAPollAFewMinutesEarlyStillCompletesTheWindow() {
        var tracker = SustainedCPUTracker()
        _ = tracker.record([process("node", cpuSeconds: 0)], at: at(0))
        let early = tracker.record([process("node", cpuSeconds: 2800)], at: at(57))
        XCTAssertTrue(early.coversWindow)
        XCTAssertEqual(early.usage.first?.averageCores ?? 0, 2800 / (57 * 60), accuracy: 0.001)

        var tooEarly = SustainedCPUTracker()
        _ = tooEarly.record([process("node", cpuSeconds: 0)], at: at(0))
        XCTAssertTrue(tooEarly.record([process("node", cpuSeconds: 2800)], at: at(50)).usage.isEmpty)
    }

    func testAReusedPidStartsItsOwnHistory() {
        var tracker = SustainedCPUTracker()
        _ = tracker.record([process("old", pid: 7, started: 1, cpuSeconds: 0)], at: at(0))
        let reused = tracker.record([process("new", pid: 7, started: 2, cpuSeconds: 5000)], at: at(60))
        XCTAssertTrue(reused.usage.isEmpty, "a different start time is a different process")
        XCTAssertTrue(reused.coversWindow, "the tracker itself has watched for an hour")
    }

    func testAnExitedProcessIsForgotten() {
        var tracker = SustainedCPUTracker()
        _ = tracker.record([process("gone", cpuSeconds: 0)], at: at(0))
        _ = tracker.record([], at: at(30))
        // Back with the same identity (impossible in practice): no stale baseline survives.
        XCTAssertTrue(tracker.record([process("gone", cpuSeconds: 3600)], at: at(60)).usage.isEmpty)
    }

    func testACounterThatWentBackwardsIsNotTrusted() {
        var tracker = SustainedCPUTracker()
        _ = tracker.record([process("odd", cpuSeconds: 5000)], at: at(0))
        XCTAssertTrue(tracker.record([process("odd", cpuSeconds: 10)], at: at(60)).usage.isEmpty)
    }

    func testALongPauseStartsOver() {
        var tracker = SustainedCPUTracker()
        _ = tracker.record([process("Xcode", cpuSeconds: 0)], at: at(0))
        let afterSleep = tracker.record([process("Xcode", cpuSeconds: 100)], at: at(5 * 60))
        XCTAssertTrue(afterSleep.usage.isEmpty, "readings older than four hours are dropped")
        XCTAssertFalse(afterSleep.coversWindow)
    }

    func testBusiestComesFirst() {
        var tracker = SustainedCPUTracker()
        _ = tracker.record([process("a", pid: 1, cpuSeconds: 0), process("b", pid: 2, cpuSeconds: 0)], at: at(0))
        let outcome = tracker.record([process("a", pid: 1, cpuSeconds: 600), process("b", pid: 2, cpuSeconds: 3000)], at: at(60))
        XCTAssertEqual(outcome.usage.map(\.name), ["b", "a"])
    }
}

final class ConditionRunTests: XCTestCase {
    func testARunStartsAtTheFirstPollThatHoldsAndBreaksOnAGap() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var run = ConditionRun()
        XCTAssertNil(run.record(holds: false, at: start))
        XCTAssertEqual(run.record(holds: true, at: start), start)
        XCTAssertEqual(run.record(holds: true, at: start.addingTimeInterval(15 * 60)), start)
        XCTAssertNil(run.record(holds: false, at: start.addingTimeInterval(30 * 60)))
        let again = start.addingTimeInterval(45 * 60)
        XCTAssertEqual(run.record(holds: true, at: again), again)
        let afterSleep = again.addingTimeInterval(3 * 3600)
        XCTAssertEqual(run.record(holds: true, at: afterSleep), afterSleep, "a long gap is not a sustained run")
    }
}
