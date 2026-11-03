import XCTest
@testable import ShortkingCore

final class ClaimTests: XCTestCase {
    func testIdentitySeparatesDelimiterBearingFields() {
        let first = Claim(
            combo: KeyCombo(character: "g", modifiers: .command),
            layer: .windowServer, status: .known,
            owner: Owner(name: "App"), label: "Menu|k0|m1|Action"
        )
        let second = Claim(
            combo: KeyCombo(character: "a", modifiers: .command),
            layer: .windowServer, status: .known,
            owner: Owner(name: "App|k5|m1|Menu"), label: "Action"
        )

        XCTAssertNotEqual(first.identity, second.identity)
    }
}
