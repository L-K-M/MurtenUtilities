import MurtenCore

/// What Coreography's watcher may read, and nothing else: no method writes,
/// signals a process, needs privilege or can prompt. The live reader wraps
/// the engine's unprivileged drivers; tests pass fixtures.
public protocol SystemObserving: Sendable {
    /// Cumulative CPU time of every process this user may read. Processes
    /// of other users need privilege and are left out, not failed.
    func processCPUTimes() async -> Result<[ProcessCPUTime], ObservationFailure>
    func memoryPressure() async -> Result<ObservedMemoryPressure, ObservationFailure>
    func thermalPressure() async -> Result<ObservedThermalPressure, ObservationFailure>
    func startupVolume() async -> Result<VolumeSpace, ObservationFailure>
}

/// One process's CPU time so far. `pid` and `startedAt` together name it,
/// so a reused pid never continues another process's history.
public struct ProcessCPUTime: Hashable, Sendable {
    public let pid: Int32
    /// Start time in microseconds since 1970, as the kernel reports it.
    public let startedAt: UInt64
    public let name: String
    /// User plus system time, in nanoseconds.
    public let cpuNanoseconds: UInt64

    public init(pid: Int32, startedAt: UInt64, name: String, cpuNanoseconds: UInt64) {
        self.pid = pid
        self.startedAt = startedAt
        self.name = name
        self.cpuNanoseconds = cpuNanoseconds
    }
}

/// The kernel's memory-pressure level.
public enum ObservedMemoryPressure: String, Comparable, CaseIterable, Sendable {
    case normal, warning, critical

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }

    private var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// The kernel's thermal-pressure level; `heavy` and above mean macOS is
/// slowing the processor to cool down.
public enum ObservedThermalPressure: String, Comparable, CaseIterable, Sendable {
    case nominal, moderate, heavy, trapping, sleeping

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }

    private var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// A volume's size and the space left for important use.
public struct VolumeSpace: Hashable, Sendable {
    public let totalBytes: Int64
    public let availableBytes: Int64

    public init(totalBytes: Int64, availableBytes: Int64) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
    }
}
