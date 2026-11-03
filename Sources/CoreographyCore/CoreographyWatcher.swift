import Foundation
import MurtenCore

/// Coreography's background check, replacing the standalone app's alerts
/// and notifications: a process that keeps a core busy for an hour,
/// sustained critical memory pressure, thermal throttling and a nearly full
/// startup disk. It only reads, through `SystemObserving`, and keeps what it
/// needs between polls (CPU time per process, when a pressure run began) in
/// memory.
///
/// Each check reports its own scope, so one failed read leaves the others'
/// suggestions alone and marks only its own as possibly outdated.
public actor CoreographyWatcher: Watcher {
    public nonisolated let moduleID = CoreographyWatch.moduleID
    public nonisolated let cadence = WatchCadence(interval: 15 * 60)

    /// At most this many busy processes per poll; the busiest come first.
    static let maximumProcessFindings = 10

    private let observer: any SystemObserving
    private let now: @Sendable () -> Date
    private var cpu = SustainedCPUTracker()
    private var criticalMemory = ConditionRun()
    private var heavyThermal = ConditionRun()

    public init(observer: any SystemObserving, now: @escaping @Sendable () -> Date = Date.init) {
        self.observer = observer
        self.now = now
    }

    public func observe() async -> WatchObservation {
        var findings: [Finding] = []
        var completed: Set<FindingScope> = []
        var failures: [ObservationFailure] = []

        func fail(_ failure: ObservationFailure, _ scope: FindingScope) {
            failures.append(ObservationFailure(kind: failure.kind, scope: scope, message: failure.message))
        }

        let processes = await observer.processCPUTimes()
        let processesRead = now()
        switch processes {
        case .success(let list):
            let outcome = cpu.record(list, at: processesRead)
            findings += busyProcesses(outcome.usage, at: processesRead)
            // Before a full window, a quiet process is not yet known to be quiet.
            if outcome.coversWindow { completed.insert(CoreographyWatch.processesScope) }
        case .failure(let failure):
            fail(failure, CoreographyWatch.processesScope)
        }
        if Task.isCancelled { return cancelled(findings, completed, failures) }

        switch await observer.memoryPressure() {
        case .success(let level):
            let time = now()
            let since = criticalMemory.record(holds: level == .critical, at: time)
            var evidence: [String: EvidenceValue] = [CoreographyWatch.Evidence.level: .text(level.rawValue)]
            if let since { evidence[CoreographyWatch.Evidence.criticalSince] = .date(since) }
            findings.append(finding(CoreographyWatch.memoryPressure, CoreographyWatch.memoryScope, time, evidence))
            completed.insert(CoreographyWatch.memoryScope)
        case .failure(let failure):
            fail(failure, CoreographyWatch.memoryScope)
        }
        if Task.isCancelled { return cancelled(findings, completed, failures) }

        switch await observer.thermalPressure() {
        case .success(let level):
            let time = now()
            let since = heavyThermal.record(holds: level >= .heavy, at: time)
            var evidence: [String: EvidenceValue] = [CoreographyWatch.Evidence.level: .text(level.rawValue)]
            if let since { evidence[CoreographyWatch.Evidence.heavySince] = .date(since) }
            findings.append(finding(CoreographyWatch.thermalPressure, CoreographyWatch.thermalScope, time, evidence))
            completed.insert(CoreographyWatch.thermalScope)
        case .failure(let failure):
            fail(failure, CoreographyWatch.thermalScope)
        }
        if Task.isCancelled { return cancelled(findings, completed, failures) }

        switch await observer.startupVolume() {
        case .success(let space) where space.totalBytes > 0:
            findings.append(finding(CoreographyWatch.startupDiskLow, CoreographyWatch.startupVolumeScope, now(), [
                CoreographyWatch.Evidence.available: .bytes(space.availableBytes),
                CoreographyWatch.Evidence.total: .bytes(space.totalBytes)
            ]))
            completed.insert(CoreographyWatch.startupVolumeScope)
        case .success:
            fail(ObservationFailure(kind: .malformedResponse, message: "The startup volume reported no size."),
                 CoreographyWatch.startupVolumeScope)
        case .failure(let failure):
            fail(failure, CoreographyWatch.startupVolumeScope)
        }

        return WatchObservation(moduleID: moduleID, observedAt: now(), findings: findings,
                           completedScopes: completed, failures: failures)
    }

    // MARK: - Findings

    /// One finding per process name, for its busiest process, and only above
    /// the rule's clear level: below it no suggestion can open or stay.
    private func busyProcesses(_ usage: [SustainedCPUTracker.Usage], at time: Date) -> [Finding] {
        var seen: Set<String> = []
        var findings: [Finding] = []
        for process in usage where process.averageCores >= CoreographyRule.clearCores {
            let name = Self.displayName(process.name)
            guard !name.isEmpty, seen.insert(name).inserted else { continue }
            findings.append(finding(CoreographyWatch.sustainedCPUCondition(name: name), CoreographyWatch.processesScope, time, [
                CoreographyWatch.Evidence.name: .text(name),
                CoreographyWatch.Evidence.pid: .count(Int(process.pid)),
                CoreographyWatch.Evidence.cpuSeconds: .seconds(process.cpuSeconds),
                CoreographyWatch.Evidence.span: .seconds(process.span)
            ]))
            if findings.count == Self.maximumProcessFindings { break }
        }
        return findings
    }

    private func finding(_ condition: String, _ scope: FindingScope, _ time: Date,
                         _ evidence: [String: EvidenceValue]) -> Finding {
        Finding(moduleID: moduleID, condition: condition, scope: scope, observedAt: time, evidence: evidence)
    }

    /// Control characters out, length bounded: the name ends up in a route.
    static func displayName(_ raw: String) -> String {
        let printable = raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let name = String(String.UnicodeScalarView(printable)).trimmingCharacters(in: .whitespaces)
        return String(name.prefix(CoreographyWatch.maximumNameLength))
    }

    /// A poll cancelled midway reports what it finished and fails the rest,
    /// so nothing unchecked resolves.
    private func cancelled(_ findings: [Finding], _ completed: Set<FindingScope>,
                           _ failures: [ObservationFailure]) -> WatchObservation {
        let cancellation = ObservationFailure(kind: .failed, message: "The check was cancelled.")
        return WatchObservation(moduleID: moduleID, observedAt: now(), findings: findings,
                           completedScopes: completed, failures: failures + [cancellation])
    }
}
