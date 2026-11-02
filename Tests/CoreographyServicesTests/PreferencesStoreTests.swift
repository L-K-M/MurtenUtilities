import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

/// Inside Murten Utilities the model keeps its settings in the module's own
/// store, never the suite app's standard domain.
final class PreferencesStoreTests: XCTestCase {
    @MainActor
    func testSettingsAreReadFromAndSavedToTheGivenStore() async throws {
        let suite = "PreferencesStoreTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        SamplingRate.twoSeconds.save(in: defaults)
        ProcessCPUScale.oneCore.save(in: defaults)

        let model = DashboardModel(
            monitor: try SystemMonitor(driver: IdleHostDriver()), interval: .milliseconds(5), preferences: defaults
        )
        XCTAssertEqual(model.samplingRate, .twoSeconds)
        XCTAssertEqual(model.processCPUScale, .oneCore)

        var layout = LaneLayout.standard
        layout.set(.gpu, .hidden)
        model.laneLayout = layout
        model.historyRetention = .extended
        model.customAlertRules = [.starter]

        XCTAssertEqual(LaneLayout.saved(in: defaults), layout)
        XCTAssertEqual(HistoryRetention.saved(in: defaults), .extended)
        XCTAssertEqual(CustomAlertRules(defaults: defaults).all.count, 1)
        XCTAssertTrue(model.preferences === defaults)
    }
}

/// A host that never changes; the test reads settings, not samples.
private actor IdleHostDriver: HostSampleReading {
    func read() async -> RawHostSnapshot {
        RawHostSnapshot(
            clockID: UUID(), monotonicNanoseconds: 0, wallTime: Date(timeIntervalSince1970: 1_700_000_000),
            inventory: HostInventory(operatingSystem: "Fixture", architecture: "fixture", logicalCPUCount: 1, physicalMemoryBytes: 1 << 20),
            cpu: .failure(.unsupportedPlatform), memory: .failure(.unsupportedPlatform),
            swap: .failure(.unsupportedPlatform), memoryPressure: .failure(.unsupportedPlatform),
            thermalPressure: .failure(.unsupportedPlatform)
        )
    }
}
