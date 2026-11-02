import Foundation

/// A daily window in local time when watchers stay quiet, e.g. 22:00–07:00.
public struct QuietHours: Codable, Equatable, Sendable {
    public static let minutesPerDay = 24 * 60

    /// Minutes after local midnight, 0..<1440.
    public let startMinute: Int
    public let endMinute: Int

    public init(startMinute: Int, endMinute: Int) {
        self.startMinute = ((startMinute % Self.minutesPerDay) + Self.minutesPerDay) % Self.minutesPerDay
        self.endMinute = ((endMinute % Self.minutesPerDay) + Self.minutesPerDay) % Self.minutesPerDay
    }

    /// Handles windows that cross midnight. An empty window (start == end)
    /// contains nothing.
    public func contains(minuteOfDay minute: Int) -> Bool {
        if startMinute == endMinute { return false }
        if startMinute < endMinute { return minute >= startMinute && minute < endMinute }
        return minute >= startMinute || minute < endMinute
    }
}

/// What the machine is doing right now, sampled by the app (power source,
/// Low Power Mode, network path, local time).
public struct WatchEnvironment: Equatable, Sendable {
    public enum PowerSource: Sendable { case adapter, battery }
    public enum NetworkCost: Sendable { case unrestricted, expensive }

    public let powerSource: PowerSource
    public let lowPowerModeEnabled: Bool
    public let networkCost: NetworkCost
    public let minuteOfDay: Int

    public init(powerSource: PowerSource, lowPowerModeEnabled: Bool,
                networkCost: NetworkCost, minuteOfDay: Int) {
        self.powerSource = powerSource
        self.lowPowerModeEnabled = lowPowerModeEnabled
        self.networkCost = networkCost
        self.minuteOfDay = minuteOfDay
    }
}

/// Whether a due poll may run now.
public enum WatchGate: Equatable, Sendable {
    public enum PauseReason: Equatable, Sendable {
        case battery
        case lowPowerMode
        case expensiveNetwork
        case quietHours
    }

    case open
    case paused(PauseReason)
}

/// The suite-wide preferences behind resident mode, watchers and
/// notifications. Everything that costs the user attention or battery is
/// off until they turn it on. Launch at login is not stored here: its truth
/// is the system's `SMAppService` status.
public struct SuiteSettings: Codable, Equatable, Sendable {
    public enum ResidentMode: String, Codable, Sendable {
        /// No menu-bar companion, no background checks. The default.
        case off
        case on
    }

    public enum UpdateChecks: String, Codable, Sendable {
        /// Never contacts GitHub on its own. The default.
        case off
        case daily
    }

    public var residentMode: ResidentMode = .off
    /// Modules whose watcher the user switched off while resident mode is on.
    public var disabledWatchers: Set<String> = []
    /// Per-module notification opt-in; empty by default.
    public var notifyingModules: Set<String> = []
    public var pauseOnBattery = true
    public var pauseInLowPowerMode = true
    public var pauseOnExpensiveNetwork = true
    public var quietHours: QuietHours?
    public var updateChecks: UpdateChecks = .off

    public init() {}

    /// The watchers that may run: none unless resident mode is on.
    public func runnableWatchers(among moduleIDs: Set<String>) -> Set<String> {
        guard residentMode == .on else { return [] }
        return moduleIDs.subtracting(disabledWatchers)
    }

    public func gate(for resources: WatchResources, in environment: WatchEnvironment) -> WatchGate {
        if let quietHours, quietHours.contains(minuteOfDay: environment.minuteOfDay) {
            return .paused(.quietHours)
        }
        if pauseInLowPowerMode, environment.lowPowerModeEnabled { return .paused(.lowPowerMode) }
        if pauseOnBattery, environment.powerSource == .battery { return .paused(.battery) }
        if pauseOnExpensiveNetwork, resources.contains(.network), environment.networkCost == .expensive {
            return .paused(.expensiveNetwork)
        }
        return .open
    }

    // MARK: - Codable

    // Missing keys fall back to defaults, so settings saved by an older build
    // keep loading after a field is added.
    private enum CodingKeys: String, CodingKey {
        case residentMode, disabledWatchers, notifyingModules, pauseOnBattery
        case pauseInLowPowerMode, pauseOnExpensiveNetwork, quietHours, updateChecks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SuiteSettings()
        residentMode = try container.decodeIfPresent(ResidentMode.self, forKey: .residentMode) ?? defaults.residentMode
        disabledWatchers = try container.decodeIfPresent(Set<String>.self, forKey: .disabledWatchers) ?? defaults.disabledWatchers
        notifyingModules = try container.decodeIfPresent(Set<String>.self, forKey: .notifyingModules) ?? defaults.notifyingModules
        pauseOnBattery = try container.decodeIfPresent(Bool.self, forKey: .pauseOnBattery) ?? defaults.pauseOnBattery
        pauseInLowPowerMode = try container.decodeIfPresent(Bool.self, forKey: .pauseInLowPowerMode) ?? defaults.pauseInLowPowerMode
        pauseOnExpensiveNetwork = try container.decodeIfPresent(Bool.self, forKey: .pauseOnExpensiveNetwork) ?? defaults.pauseOnExpensiveNetwork
        quietHours = try container.decodeIfPresent(QuietHours.self, forKey: .quietHours)
        updateChecks = try container.decodeIfPresent(UpdateChecks.self, forKey: .updateChecks) ?? defaults.updateChecks
    }
}
