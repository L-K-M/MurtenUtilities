import XCTest
@testable import MurtenCore

final class WatchScheduleTests: XCTestCase {
    private let interval: TimeInterval = 30 * 60

    func testFirstPollWaitsForLaunchToSettle() {
        var schedule = WatchSchedule()
        schedule.register(dockvac, interval: interval, at: t0)

        XCTAssertEqual(schedule.dueModules(at: t0), [])
        XCTAssertEqual(schedule.dueModules(at: at(WatchSchedule.initialDelay)), [dockvac])
    }

    func testInFlightPollIsNeverDueTwice() {
        var schedule = WatchSchedule()
        schedule.register(dockvac, interval: interval, at: t0)
        schedule.markStarted(dockvac)

        XCTAssertEqual(schedule.dueModules(at: at(10 * interval)), [])
        XCTAssertNil(schedule.nextDeadline())
    }

    func testSuccessWaitsOneIntervalAndFailuresBackOffWithACap() {
        var schedule = WatchSchedule()
        schedule.register(dockvac, interval: interval, at: t0)

        schedule.markStarted(dockvac)
        schedule.markFinished(dockvac, .succeeded, at: t0)
        XCTAssertEqual(schedule.nextDeadline(), at(interval))

        var delays: [TimeInterval] = []
        for _ in 0..<6 {
            schedule.markStarted(dockvac)
            schedule.markFinished(dockvac, .failed, at: t0)
            delays.append(schedule.nextDeadline()!.timeIntervalSince(t0))
        }
        XCTAssertEqual(delays, [interval, 2 * interval, 4 * interval, 8 * interval,
                                WatchSchedule.maximumBackoff, WatchSchedule.maximumBackoff])

        schedule.markStarted(dockvac)
        schedule.markFinished(dockvac, .succeeded, at: t0)
        XCTAssertEqual(schedule.nextDeadline(), at(interval), "success resets the back-off")
    }

    func testWakeCoalescesOverdueChecksAfterSettling() {
        var schedule = WatchSchedule()
        schedule.register(dockvac, interval: interval, at: t0)
        schedule.register("repomen", interval: interval, at: t0)

        let woke = at(10 * interval)
        schedule.wake(at: woke)
        XCTAssertEqual(schedule.dueModules(at: woke), [])
        XCTAssertEqual(schedule.dueModules(at: woke.addingTimeInterval(WatchSchedule.wakeSettleDelay)),
                       [dockvac, "repomen"])
    }

    func testPostponeAndExpedite() {
        var schedule = WatchSchedule()
        schedule.register(dockvac, interval: interval, at: t0)

        schedule.postpone(dockvac, at: at(60))
        XCTAssertEqual(schedule.nextDeadline(), at(60 + WatchSchedule.pauseRecheckInterval))

        schedule.expedite(dockvac, at: at(120))
        XCTAssertEqual(schedule.dueModules(at: at(120)), [dockvac])
    }

    func testCadenceEnforcesTheMinimumInterval() {
        XCTAssertEqual(WatchCadence(interval: 1).interval, WatchCadence.minimumInterval)
    }
}
