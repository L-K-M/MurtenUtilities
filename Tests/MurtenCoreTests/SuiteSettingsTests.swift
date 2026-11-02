import XCTest
@testable import MurtenCore

final class SuiteSettingsTests: XCTestCase {
    private func environment(power: WatchEnvironment.PowerSource = .adapter, lowPower: Bool = false,
                             network: WatchEnvironment.NetworkCost = .unrestricted,
                             minute: Int = 12 * 60) -> WatchEnvironment {
        WatchEnvironment(powerSource: power, lowPowerModeEnabled: lowPower, networkCost: network, minuteOfDay: minute)
    }

    func testEverythingAttentionCostingIsOffByDefault() {
        let settings = SuiteSettings()
        XCTAssertEqual(settings.residentMode, .off)
        XCTAssertTrue(settings.notifyingModules.isEmpty)
        XCTAssertEqual(settings.updateChecks, .off)
        XCTAssertTrue(settings.runnableWatchers(among: ["dockvac"]).isEmpty)
    }

    func testResidentModeRunsAllButDisabledWatchers() {
        var settings = SuiteSettings()
        settings.residentMode = .on
        settings.disabledWatchers = ["repomen"]
        XCTAssertEqual(settings.runnableWatchers(among: ["dockvac", "repomen"]), ["dockvac"])
    }

    func testGatePausesForBatteryLowPowerQuietHoursAndMeteredNetwork() {
        var settings = SuiteSettings()
        XCTAssertEqual(settings.gate(for: [], in: environment()), .open)
        XCTAssertEqual(settings.gate(for: [], in: environment(power: .battery)), .paused(.battery))
        XCTAssertEqual(settings.gate(for: [], in: environment(lowPower: true)), .paused(.lowPowerMode))
        XCTAssertEqual(settings.gate(for: [], in: environment(network: .expensive)), .open,
                       "local checks ignore network cost")
        XCTAssertEqual(settings.gate(for: .network, in: environment(network: .expensive)), .paused(.expensiveNetwork))

        settings.quietHours = QuietHours(startMinute: 22 * 60, endMinute: 7 * 60)
        XCTAssertEqual(settings.gate(for: [], in: environment(minute: 23 * 60)), .paused(.quietHours))

        settings.pauseOnBattery = false
        settings.quietHours = nil
        XCTAssertEqual(settings.gate(for: [], in: environment(power: .battery)), .open)
    }

    func testQuietHoursHandleMidnightAndEmptyWindows() {
        let overnight = QuietHours(startMinute: 22 * 60, endMinute: 7 * 60)
        XCTAssertTrue(overnight.contains(minuteOfDay: 23 * 60))
        XCTAssertTrue(overnight.contains(minuteOfDay: 6 * 60 + 59))
        XCTAssertFalse(overnight.contains(minuteOfDay: 7 * 60))
        XCTAssertFalse(overnight.contains(minuteOfDay: 12 * 60))

        let lunch = QuietHours(startMinute: 12 * 60, endMinute: 13 * 60)
        XCTAssertTrue(lunch.contains(minuteOfDay: 12 * 60 + 30))
        XCTAssertFalse(lunch.contains(minuteOfDay: 13 * 60))

        XCTAssertFalse(QuietHours(startMinute: 60, endMinute: 60).contains(minuteOfDay: 60))
    }

    func testDecodingFillsMissingKeysWithDefaults() throws {
        let settings = try JSONDecoder().decode(SuiteSettings.self, from: Data(#"{"residentMode": "on"}"#.utf8))
        XCTAssertEqual(settings.residentMode, .on)
        XCTAssertTrue(settings.pauseOnBattery)
        XCTAssertEqual(settings.updateChecks, .off)
    }
}
