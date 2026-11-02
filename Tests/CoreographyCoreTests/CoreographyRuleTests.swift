import Foundation
import XCTest
import MurtenCore
@testable import CoreographyCore

final class CoreographyRuleTests: XCTestCase {
    private let rule = CoreographyRule()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func cpu(_ name: String, cores: Double, span: TimeInterval = 3600) -> Finding {
        Finding(moduleID: CoreographyWatch.moduleID, condition: CoreographyWatch.sustainedCPUCondition(name: name),
                scope: CoreographyWatch.processesScope, observedAt: now, evidence: [
                    CoreographyWatch.Evidence.name: .text(name),
                    CoreographyWatch.Evidence.pid: .count(42),
                    CoreographyWatch.Evidence.cpuSeconds: .seconds(cores * span),
                    CoreographyWatch.Evidence.span: .seconds(span)
                ])
    }

    private func pressure(_ condition: String, _ level: String, sinceKey: String, heldMinutes: Double?) -> Finding {
        var evidence: [String: EvidenceValue] = [CoreographyWatch.Evidence.level: .text(level)]
        if let heldMinutes { evidence[sinceKey] = .date(now.addingTimeInterval(-heldMinutes * 60)) }
        let scope = condition == CoreographyWatch.memoryPressure ? CoreographyWatch.memoryScope : CoreographyWatch.thermalScope
        return Finding(moduleID: CoreographyWatch.moduleID, condition: condition, scope: scope, observedAt: now, evidence: evidence)
    }

    private func disk(available: Int64, total: Int64 = 1_000_000_000_000) -> Finding {
        Finding(moduleID: CoreographyWatch.moduleID, condition: CoreographyWatch.startupDiskLow,
                scope: CoreographyWatch.startupVolumeScope, observedAt: now, evidence: [
                    CoreographyWatch.Evidence.available: .bytes(available),
                    CoreographyWatch.Evidence.total: .bytes(total)
                ])
    }

    func testABusyProcessOpensAboveRaiseAndStaysAboveClear() throws {
        XCTAssertNil(rule.suggestion(for: cpu("Xcode", cores: 0.7), state: .inactive))
        let opened = try XCTUnwrap(rule.suggestion(for: cpu("Xcode", cores: 0.85), state: .inactive))
        XCTAssertEqual(opened.title, "Xcode has kept a CPU core busy for an hour")
        XCTAssertTrue(opened.detail.contains("85 %"))
        XCTAssertEqual(opened.route, ModuleRoute(moduleID: "coreography", action: "process", context: ["name": "Xcode"]))

        XCTAssertNotNil(rule.suggestion(for: cpu("Xcode", cores: 0.6), state: .active), "hysteresis keeps it open")
        XCTAssertNil(rule.suggestion(for: cpu("Xcode", cores: 0.4), state: .active))
    }

    func testMemoryOpensOnlyOnSustainedCriticalPressure() {
        let key = CoreographyWatch.Evidence.criticalSince
        let memory = CoreographyWatch.memoryPressure
        XCTAssertNil(rule.suggestion(for: pressure(memory, "critical", sinceKey: key, heldMinutes: 0), state: .inactive),
                     "one critical check is not sustained")
        XCTAssertNil(rule.suggestion(for: pressure(memory, "warning", sinceKey: key, heldMinutes: nil), state: .inactive))
        XCTAssertNotNil(rule.suggestion(for: pressure(memory, "critical", sinceKey: key, heldMinutes: 15), state: .inactive))
        XCTAssertNotNil(rule.suggestion(for: pressure(memory, "warning", sinceKey: key, heldMinutes: nil), state: .active))
        XCTAssertNil(rule.suggestion(for: pressure(memory, "normal", sinceKey: key, heldMinutes: nil), state: .active))
    }

    func testThermalOpensOnSustainedHeavyPressure() {
        let key = CoreographyWatch.Evidence.heavySince
        let thermal = CoreographyWatch.thermalPressure
        XCTAssertNil(rule.suggestion(for: pressure(thermal, "moderate", sinceKey: key, heldMinutes: nil), state: .inactive))
        XCTAssertNil(rule.suggestion(for: pressure(thermal, "heavy", sinceKey: key, heldMinutes: 5), state: .inactive))
        XCTAssertNotNil(rule.suggestion(for: pressure(thermal, "trapping", sinceKey: key, heldMinutes: 15), state: .inactive))
        XCTAssertNotNil(rule.suggestion(for: pressure(thermal, "moderate", sinceKey: key, heldMinutes: nil), state: .active))
        XCTAssertNil(rule.suggestion(for: pressure(thermal, "nominal", sinceKey: key, heldMinutes: nil), state: .active))
        XCTAssertNil(rule.suggestion(for: pressure(thermal, "unknown", sinceKey: key, heldMinutes: 30), state: .active),
                     "an unreadable level never keeps or opens one")
    }

    func testStartupDiskOpensUnderTenPercentAndClearsAtTwelve() throws {
        XCTAssertNil(rule.suggestion(for: disk(available: 110_000_000_000), state: .inactive))
        let opened = try XCTUnwrap(rule.suggestion(for: disk(available: 80_000_000_000), state: .inactive))
        XCTAssertTrue(opened.detail.hasPrefix("Only 80.0 GB of 1.0 TB is free (8 %)."), opened.detail)
        XCTAssertNotNil(rule.suggestion(for: disk(available: 110_000_000_000), state: .active))
        XCTAssertNil(rule.suggestion(for: disk(available: 130_000_000_000), state: .active))
        XCTAssertNil(rule.suggestion(for: disk(available: 1, total: 0), state: .inactive))
    }

    func testFindingsOfOtherModulesOrConditionsAreIgnored() {
        let other = Finding(moduleID: "dockvac", condition: CoreographyWatch.startupDiskLow, observedAt: now,
                            evidence: [CoreographyWatch.Evidence.available: .bytes(0), CoreographyWatch.Evidence.total: .bytes(1)])
        XCTAssertNil(rule.suggestion(for: other, state: .inactive))
        XCTAssertNil(rule.suggestion(for: Finding(moduleID: "coreography", condition: "unknown", observedAt: now), state: .active))
    }

    func testEverySuggestionRoutePassesTheAllowlist() throws {
        let routes = [
            rule.suggestion(for: cpu("Google Chrome Helper (Renderer)", cores: 1), state: .inactive)?.route,
            rule.suggestion(for: pressure(CoreographyWatch.memoryPressure, "critical",
                                          sinceKey: CoreographyWatch.Evidence.criticalSince, heldMinutes: 20), state: .inactive)?.route,
            rule.suggestion(for: pressure(CoreographyWatch.thermalPressure, "heavy",
                                          sinceKey: CoreographyWatch.Evidence.heavySince, heldMinutes: 20), state: .inactive)?.route,
            rule.suggestion(for: disk(available: 1), state: .inactive)?.route
        ]
        for route in routes {
            let route = try XCTUnwrap(route)
            XCTAssertEqual(try coreographyAllowlist.validate(route), route)
            XCTAssertEqual(try coreographyAllowlist.route(from: route.url), route, "survives a notification round trip")
        }
    }
}
