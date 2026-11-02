import Foundation
import MurtenCore
@testable import CoreographyCore

/// A clock the test moves by hand.
final class FixtureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func advance(minutes: Double) {
        lock.lock(); defer { lock.unlock() }
        current = current.addingTimeInterval(minutes * 60)
    }
}

/// Scripted readings: each property is what the next poll reads.
final class FixtureSystem: SystemObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var _processes: Result<[ProcessCPUTime], ObservationFailure> = .success([])
    private var _memory: Result<ObservedMemoryPressure, ObservationFailure> = .success(.normal)
    private var _thermal: Result<ObservedThermalPressure, ObservationFailure> = .success(.nominal)
    private var _volume: Result<VolumeSpace, ObservationFailure> = .success(VolumeSpace(totalBytes: 1_000_000_000_000,
                                                                                        availableBytes: 500_000_000_000))

    var processes: Result<[ProcessCPUTime], ObservationFailure> {
        get { locked { _processes } }
        set { locked { _processes = newValue } }
    }

    var memory: Result<ObservedMemoryPressure, ObservationFailure> {
        get { locked { _memory } }
        set { locked { _memory = newValue } }
    }

    var thermal: Result<ObservedThermalPressure, ObservationFailure> {
        get { locked { _thermal } }
        set { locked { _thermal = newValue } }
    }

    var volume: Result<VolumeSpace, ObservationFailure> {
        get { locked { _volume } }
        set { locked { _volume = newValue } }
    }

    func processCPUTimes() async -> Result<[ProcessCPUTime], ObservationFailure> { processes }
    func memoryPressure() async -> Result<ObservedMemoryPressure, ObservationFailure> { memory }
    func thermalPressure() async -> Result<ObservedThermalPressure, ObservationFailure> { thermal }
    func startupVolume() async -> Result<VolumeSpace, ObservationFailure> { volume }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
}

/// A process that has used `seconds` of CPU so far.
func process(_ name: String, pid: Int32 = 100, started: UInt64 = 1, cpuSeconds: Double) -> ProcessCPUTime {
    ProcessCPUTime(pid: pid, startedAt: started, name: name, cpuNanoseconds: UInt64(cpuSeconds * 1_000_000_000))
}

let unreachable = ObservationFailure(kind: .unreachable, message: "fixture failure")

/// Every route a suggestion may carry must pass the suite's allowlist.
let coreographyAllowlist = RouteAllowlist(modules: [CoreographyWatch.moduleID],
                                          actions: [CoreographyWatch.moduleID: CoreographyWatch.routeActions])
