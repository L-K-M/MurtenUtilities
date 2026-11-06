import XCTest
import Observation
import os
import MurtenCore
@testable import MurtenShell

@MainActor
final class SuiteScenesTests: XCTestCase {
    func testMenuInsertionWritebackDoesNotInvalidateUnchangedSettings() {
        for mode in [SuiteSettings.ResidentMode.off, .on] {
            var settings = SuiteSettings()
            settings.residentMode = mode
            let harness = Harness(settings: settings)
            let binding = SuiteScenes(model: harness.model).residentBinding
            let invalidations = OSAllocatedUnfairLock(initialState: 0)

            withObservationTracking {
                _ = harness.model.settings
            } onChange: {
                invalidations.withLock { $0 += 1 }
            }

            // MenuBarExtra writes its current insertion state back at startup.
            binding.wrappedValue = mode == .on

            XCTAssertEqual(invalidations.withLock { $0 }, 0, "Unchanged \(mode) must not rebuild the scene")
            XCTAssertEqual(harness.model.settings, settings)
        }
    }

    func testMenuInsertionChangesPersistResidentMode() {
        var settings = SuiteSettings()
        settings.residentMode = .on
        let harness = Harness(settings: settings)
        let binding = SuiteScenes(model: harness.model).residentBinding

        binding.wrappedValue = false
        XCTAssertEqual(harness.model.settings.residentMode, .off)
        XCTAssertEqual(harness.settings.stored.residentMode, .off)

        binding.wrappedValue = true
        XCTAssertEqual(harness.model.settings.residentMode, .on)
        XCTAssertEqual(harness.settings.stored.residentMode, .on)
    }
}
