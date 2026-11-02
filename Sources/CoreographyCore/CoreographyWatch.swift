import MurtenCore

/// The words Coreography's watcher, rule and pane share: what a finding is
/// about, what it carries, and where a suggestion leads.
///
///     scope            condition                 evidence
///     processes        sustained-cpu:<name>      name, pid, cpuSeconds, span
///     memory           memory-pressure           level, criticalSince?
///     thermal          thermal-pressure          level, heavySince?
///     startup-volume   startup-disk-low          available, total
///
/// A process's name is part of its condition, not its scope: one poll checks
/// every readable process at once, so when a process exits, the completed
/// `processes` scope resolves its suggestion, including one restored from
/// an earlier launch.
public enum CoreographyWatch {
    public static let moduleID = "coreography"

    // MARK: Scopes

    public static let processesScope = FindingScope("processes")
    public static let memoryScope = FindingScope("memory")
    public static let thermalScope = FindingScope("thermal")
    public static let startupVolumeScope = FindingScope("startup-volume")

    // MARK: Conditions

    public static let sustainedCPUPrefix = "sustained-cpu:"
    public static let memoryPressure = "memory-pressure"
    public static let thermalPressure = "thermal-pressure"
    public static let startupDiskLow = "startup-disk-low"

    /// Names longer than this are cut, so a condition and a route value stay short.
    public static let maximumNameLength = 64

    public static func sustainedCPUCondition(name: String) -> String {
        sustainedCPUPrefix + name
    }

    // MARK: Evidence keys

    public enum Evidence {
        public static let name = "name"
        public static let pid = "pid"
        /// CPU time the process used over `span`.
        public static let cpuSeconds = "cpuSeconds"
        public static let span = "span"
        public static let level = "level"
        public static let criticalSince = "criticalSince"
        public static let heavySince = "heavySince"
        public static let available = "available"
        public static let total = "total"
    }

    // MARK: Routes

    /// Actions a route may name and the context each accepts. They only
    /// navigate: filter or sort the process table, or show the sensors.
    public enum Action {
        /// The process table filtered to `name`, busiest first.
        public static let process = "process"
        /// The process table by memory.
        public static let memory = "memory"
        /// The sensors pane.
        public static let thermal = "thermal"
        /// The process table by disk writes.
        public static let storage = "storage"
    }

    public static let nameContextKey = "name"

    public static let routeActions: [String: Set<String>] = [
        Action.process: [nameContextKey],
        Action.memory: [],
        Action.thermal: [],
        Action.storage: []
    ]

    public static func route(_ action: String, context: [String: String] = [:]) -> ModuleRoute {
        ModuleRoute(moduleID: moduleID, action: action, context: context)
    }
}
