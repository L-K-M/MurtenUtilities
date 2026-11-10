import CoreGraphics
import XCTest
@testable import ShortkingKit

final class SnifferRearmTests: XCTestCase {
    /// macOS can switch a tap off (timeout, user input). It tells the callback,
    /// and a tap that is not switched back on stays dead while the panel still
    /// says it is listening.
    func testATapTheSystemDisabledIsSwitchedBackOn() throws {
        let context = SnifferContext(pid: getpid(), ownerName: "test", bundleID: nil) { _ in }
        let boxed = Unmanaged.passRetained(context)
        defer { boxed.release() }

        let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(EventTapScanner.systemDefinedMask),
            callback: shortkingSniffCallback, userInfo: boxed.toOpaque())
        // Without Input Monitoring no tap can be created, as on a CI runner.
        guard let tap = port else { throw XCTSkip("creating an event tap needs Input Monitoring") }
        defer { CFMachPortInvalidate(tap) }
        context.port = tap

        let event = try XCTUnwrap(CGEvent(source: nil))
        let proxy = try XCTUnwrap(OpaquePointer(bitPattern: 1))
        for reason in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput] {
            CGEvent.tapEnable(tap: tap, enable: false)
            XCTAssertFalse(CGEvent.tapIsEnabled(tap: tap))
            _ = shortkingSniffCallback(proxy: proxy, type: reason, event: event, userInfo: boxed.toOpaque())
            XCTAssertTrue(CGEvent.tapIsEnabled(tap: tap), "the tap must be listening again")
        }
    }
}
