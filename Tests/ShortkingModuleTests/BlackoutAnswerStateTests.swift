import XCTest
@testable import ShortkingModule

final class BlackoutAnswerStateTests: XCTestCase {
    func testAnswersRequireCompletedTestForCurrentTarget() {
        var state = BlackoutAnswerState()
        XCTAssertFalse(state.canReport)
        state.began()
        state.ended()
        XCTAssertTrue(state.canReport)
        state.targetChanged()
        XCTAssertFalse(state.canReport)
        state.began()
        state.ended()
        state.began()
        XCTAssertFalse(state.canReport)
    }

    func testTargetChangeDuringBlackoutInvalidatesCompletion() {
        var state = BlackoutAnswerState()
        state.began()
        state.targetChanged()
        state.ended()
        XCTAssertFalse(state.canReport)
    }
}
