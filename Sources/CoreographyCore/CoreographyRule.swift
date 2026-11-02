import Foundation
import MurtenCore

/// Turns the watcher's findings into suggestions, with hysteresis: a level
/// opens a suggestion and a lower one keeps it open, so a reading that
/// hovers at a threshold does not open and close episodes. Pure: it reads
/// only the finding and whether its suggestion is already active.
///
/// | Condition | Opens | Stays open while |
/// | --- | --- | --- |
/// | sustained CPU | ≥ 0.8 of a core over the last hour | ≥ 0.5 of a core |
/// | memory pressure | critical at two checks in a row | warning or critical |
/// | thermal pressure | heavy or worse at two checks in a row | moderate or worse |
/// | startup disk | under 10 % free | under 12 % free |
public struct CoreographyRule: SuggestionRule {
    public static let raiseCores = 0.8
    public static let clearCores = 0.5
    /// Two checks 15 minutes apart, with room for a poll that runs early.
    public static let sustainedPressure: TimeInterval = 10 * 60
    public static let lowDiskFraction = 0.10
    public static let clearDiskFraction = 0.12

    public init() {}

    public func suggestion(for finding: Finding, state: RuleState) -> SuggestionContent? {
        guard finding.moduleID == CoreographyWatch.moduleID else { return nil }

        switch finding.condition {
        case CoreographyWatch.memoryPressure: return memory(finding, state)
        case CoreographyWatch.thermalPressure: return thermal(finding, state)
        case CoreographyWatch.startupDiskLow: return disk(finding, state)
        case let condition where condition.hasPrefix(CoreographyWatch.sustainedCPUPrefix): return cpu(finding, state)
        default: return nil
        }
    }

    // MARK: - Conditions

    private func cpu(_ finding: Finding, _ state: RuleState) -> SuggestionContent? {
        typealias Key = CoreographyWatch.Evidence
        guard let name = finding.text(Key.name), let cpuSeconds = finding.seconds(Key.cpuSeconds),
              let span = finding.seconds(Key.span), span > 0 else { return nil }

        let cores = cpuSeconds / span
        guard cores >= (state == .active ? Self.clearCores : Self.raiseCores) else { return nil }

        let percent = Int((cores * 100).rounded())
        let minutes = Int((span / 60).rounded())
        return SuggestionContent(
            title: "\(name) has kept a CPU core busy for an hour",
            detail: "It averaged \(percent) % of one core over the last \(minutes) minutes. "
                + "Open Coreography to see what it is doing; nothing is quit unless you choose to.",
            route: CoreographyWatch.route(CoreographyWatch.Action.process, context: [CoreographyWatch.nameContextKey: name]))
    }

    private func memory(_ finding: Finding, _ state: RuleState) -> SuggestionContent? {
        guard let level = finding.text(CoreographyWatch.Evidence.level).flatMap(ObservedMemoryPressure.init(rawValue:)) else {
            return nil
        }

        switch state {
        case .active:
            guard level >= .warning else { return nil }
        case .inactive:
            guard level == .critical, held(finding, since: CoreographyWatch.Evidence.criticalSince) else { return nil }
        }
        return SuggestionContent(
            title: "Memory is running out",
            detail: "macOS has reported critical memory pressure at two checks in a row, so apps may slow down "
                + "while it compresses and swaps memory. Open Coreography to see which apps use the most.",
            route: CoreographyWatch.route(CoreographyWatch.Action.memory))
    }

    private func thermal(_ finding: Finding, _ state: RuleState) -> SuggestionContent? {
        guard let level = finding.text(CoreographyWatch.Evidence.level).flatMap(ObservedThermalPressure.init(rawValue:)) else {
            return nil
        }

        switch state {
        case .active:
            guard level >= .moderate else { return nil }
        case .inactive:
            guard level >= .heavy, held(finding, since: CoreographyWatch.Evidence.heavySince) else { return nil }
        }
        return SuggestionContent(
            title: "Your Mac is slowing down to stay cool",
            detail: "Thermal pressure was heavy at two checks in a row, so macOS is limiting the processor. "
                + "Open Coreography to see what keeps it busy and how warm it runs.",
            route: CoreographyWatch.route(CoreographyWatch.Action.thermal))
    }

    private func disk(_ finding: Finding, _ state: RuleState) -> SuggestionContent? {
        guard let available = finding.bytes(CoreographyWatch.Evidence.available),
              let total = finding.bytes(CoreographyWatch.Evidence.total), total > 0 else { return nil }

        let fraction = Double(max(available, 0)) / Double(total)
        guard fraction < (state == .active ? Self.clearDiskFraction : Self.lowDiskFraction) else { return nil }

        let percent = Int((fraction * 100).rounded())
        return SuggestionContent(
            title: "The startup disk is nearly full",
            detail: "Only \(Self.size(available)) of \(Self.size(total)) is free (\(percent) %). "
                + "macOS needs free space for updates, swap and caches. Open Coreography to see what is writing to disk.",
            route: CoreographyWatch.route(CoreographyWatch.Action.storage))
    }

    // MARK: - Helpers

    private func held(_ finding: Finding, since key: String) -> Bool {
        guard let since = finding.date(key) else { return false }
        return finding.observedAt.timeIntervalSince(since) >= Self.sustainedPressure
    }

    /// "80.0 GB", "1.0 TB": the decimal units Finder uses, formatted the
    /// same on every platform.
    static func size(_ bytes: Int64) -> String {
        let terabyte = 1_000_000_000_000.0
        let value = Double(bytes)
        return value >= terabyte
            ? String(format: "%.1f TB", value / terabyte)
            : String(format: "%.1f GB", value / 1_000_000_000)
    }
}
