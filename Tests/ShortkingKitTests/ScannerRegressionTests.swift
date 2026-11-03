import Foundation
import XCTest
import ShortkingCore
@testable import ShortkingKit

final class ScannerRegressionTests: XCTestCase {
    func testSymbolicCharacterValidation() {
        XCTAssertEqual(SymbolicHotKeyParsing.character(0x1F642), "🙂")
        XCTAssertNil(SymbolicHotKeyParsing.character(0xD800))
        XCTAssertNil(SymbolicHotKeyParsing.character(-1))
        XCTAssertNil(SymbolicHotKeyParsing.character(65535))
    }

    func testOversizedSymbolicCharacterDoesNotTrap() {
        XCTAssertNil(SymbolicHotKeyParsing.character(Int(UInt32.max) + 1))
    }

    func testLiveEnabledStateOverridesPlistWhenAvailable() {
        let combo = KeyCombo(character: "g", modifiers: .command)
        for plistEnabled in [false, true] {
            let plist = Claim(combo: combo, layer: .symbolic, status: .known, enabled: plistEnabled)
            let live = Claim(combo: combo, layer: .symbolic, status: .known, enabled: !plistEnabled)
            XCTAssertEqual(SymbolicHotKeyParsing.merge(plist: plist, live: live,
                liveEnabled: !plistEnabled).enabled, !plistEnabled)
            XCTAssertEqual(SymbolicHotKeyParsing.merge(plist: plist, live: live,
                liveEnabled: nil).enabled, plistEnabled)
        }
    }

    func testMenuCacheDistinguishesFailedWalkFromEmptyMenu() {
        XCTAssertNil(MenuWalkResult<Int>.incomplete.cacheableEntries)
        XCTAssertEqual(MenuWalkResult<Int>.complete([]).cacheableEntries, [])
        XCTAssertEqual(MenuWalkResult.complete([1]).cacheableEntries, [1])
    }

    func testMenuWalkDeadlineBoundsEveryRead() throws {
        let start = Date(timeIntervalSince1970: 100)
        let budget = MenuWalkBudget(startedAt: start)
        XCTAssertEqual(try budget.readTimeout(now: start), Float(MenuWalkBudget.messagingTimeout))
        let nearDeadline = start.addingTimeInterval(MenuWalkBudget.appDuration - 0.01)
        XCTAssertLessThanOrEqual(try budget.readTimeout(now: nearDeadline), 0.011)
        XCTAssertThrowsError(try budget.readTimeout(now: start.addingTimeInterval(MenuWalkBudget.appDuration)))
    }

    func testMenuWalkStopsOnCancellation() async {
        let task = Task<Void, Never> {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try MenuWalkBudget().readTimeout()
                XCTFail("Cancelled menu traversal must stop")
            } catch {}
        }
        await task.value
    }

    func testMenuWalkMarksOverdeepTreesIncompleteAndContinuesSiblings() throws {
        var budget = MenuWalkBudget()

        XCTAssertFalse(try budget.visit(depth: MenuWalkBudget.maximumDepth + 1))
        XCTAssertTrue(try budget.visit(depth: 0))
        XCTAssertTrue(budget.wasTruncated)
    }
}
