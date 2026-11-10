import CoreGraphics
import XCTest
@testable import ShortkingKit

final class HealthCheckTests: XCTestCase {
    /// The Input Monitoring probe creates an event tap to see whether it may.
    /// Every scan runs it, so a tap it left registered would pile up for the
    /// life of the app.
    func testInputMonitoringProbeLeavesNoEventTapBehind() throws {
        // Without Input Monitoring no tap is created and this would hold trivially.
        try XCTSkipUnless(CGPreflightListenEventAccess(), "creating an event tap needs Input Monitoring")
        let before = Self.ownEventTaps()
        for _ in 0..<3 { _ = HealthChecker.inputMonitoringCheck() }
        XCTAssertEqual(Self.ownEventTaps(), before)
    }

    /// Event taps this process has registered with the window server.
    private static func ownEventTaps() -> Int {
        var count: UInt32 = 0
        guard CGGetEventTapList(0, nil, &count) == .success, count > 0 else { return 0 }
        var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
        guard CGGetEventTapList(count, &taps, &count) == .success else { return 0 }
        return taps.prefix(Int(count)).filter { $0.tappingProcess == getpid() }.count
    }
}
