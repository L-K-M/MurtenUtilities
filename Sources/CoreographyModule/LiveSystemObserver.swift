import Foundation
import MurtenCore
import CoreographyCore
import CoreographyDrivers

/// The watcher's reads on this Mac, through the engine's own unprivileged
/// drivers: libproc for the user's processes, the kernel's pressure
/// levels, and the startup volume's resource values. Nothing here writes,
/// signals, asks the privileged helper or touches a protected folder.
struct LiveSystemObserver: SystemObserving {
    private let host = HostStatisticsDriver()
    private let processes = ProcessStatisticsDriver()
    private let volumes = VolumeCapacityDriver()

    func processCPUTimes() async -> Result<[ProcessCPUTime], ObservationFailure> {
        let snapshot = await processes.read()
        switch snapshot.enumeration {
        case .failure(let error):
            return .failure(ObservationFailure(kind: Self.kind(error), message: "Processes could not be listed (\(error))."))
        case .success(let enumeration):
            // A cut-off list would make a missing process look quiet.
            guard !enumeration.isTruncated else {
                return .failure(ObservationFailure(kind: .malformedResponse, message: "The process list was cut short."))
            }
            return .success(enumeration.processes.compactMap(Self.cpuTime))
        }
    }

    func memoryPressure() async -> Result<ObservedMemoryPressure, ObservationFailure> {
        switch await host.read().memoryPressure {
        case .success(.normal): .success(.normal)
        case .success(.warning): .success(.warning)
        case .success(.critical): .success(.critical)
        case .failure(let error): .failure(Self.failure(error, reading: "Memory pressure"))
        }
    }

    func thermalPressure() async -> Result<ObservedThermalPressure, ObservationFailure> {
        switch await host.read().thermalPressure {
        case .success(.nominal): .success(.nominal)
        case .success(.moderate): .success(.moderate)
        case .success(.heavy): .success(.heavy)
        case .success(.trapping): .success(.trapping)
        case .success(.sleeping): .success(.sleeping)
        case .failure(let error): .failure(Self.failure(error, reading: "Thermal pressure"))
        }
    }

    func startupVolume() async -> Result<VolumeSpace, ObservationFailure> {
        switch await volumes.startupVolume() {
        case .success(let capacity):
            .success(VolumeSpace(totalBytes: capacity.totalBytes, availableBytes: capacity.availableBytes))
        case .failure(.unavailable(let reason)):
            .failure(ObservationFailure(kind: .failed, message: reason))
        case .failure(.unsupportedPlatform):
            .failure(ObservationFailure(kind: .toolMissing, message: "The startup volume cannot be read on this system."))
        }
    }

    // MARK: - Mapping

    /// Other users' processes need the helper to read; they are skipped,
    /// so the watcher only ever speaks for the person's own processes.
    private static func cpuTime(_ info: RawProcessInfo) -> ProcessCPUTime? {
        guard case .success(let counters) = info.counters else { return nil }
        // The executable's name is what people recognise ("Google Chrome
        // Helper (Renderer)"); the kernel's short name is the fallback.
        let name = info.executablePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? info.name
        return ProcessCPUTime(
            pid: info.pid, startedAt: info.startSeconds &* 1_000_000 &+ info.startMicroseconds, name: name,
            cpuNanoseconds: counters.userNanoseconds &+ counters.systemNanoseconds)
    }

    private static func kind(_ error: ProcessDriverError) -> ObservationFailure.Kind {
        switch error {
        case .unsupportedPlatform: .toolMissing
        case .restricted: .permissionDenied
        case .disappeared, .identityChanged, .systemCall: .failed
        }
    }

    private static func failure(_ error: HostDriverError, reading: String) -> ObservationFailure {
        switch error {
        case .unsupportedPlatform:
            ObservationFailure(kind: .toolMissing, message: "\(reading) cannot be read on this system.")
        case .malformedReply, .unexpectedValue, .invalidPageSize:
            ObservationFailure(kind: .malformedResponse, message: "\(reading) could not be read (\(error)).")
        case .systemCall:
            ObservationFailure(kind: .failed, message: "\(reading) could not be read (\(error)).")
        }
    }
}
