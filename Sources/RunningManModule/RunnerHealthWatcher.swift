import Foundation
import MurtenCore
import RunningManCore
import RunningManServices

/// What RunningMan remembers about runner health, shared by the background check and the
/// pane: the pane's refreshes date when a runner went offline, and a stop asked for in
/// the pane is not reported as an outage. In memory only.
actor RunnerHealthMemoryStore {
    private var memory = RunnerHealthMemory()

    func acknowledgeStop(of runnerID: String, at date: Date) {
        memory.acknowledgeStop(of: runnerID, at: date)
    }

    func record(_ snapshots: [RunnerSnapshot], at date: Date) {
        memory.record(snapshots, at: date)
    }

    func observation(of reading: RunnerStateReading, at date: Date) -> WatchObservation {
        RunnerHealthCheck.observation(of: reading.snapshots, skippedDirectories: reading.skippedDirectories,
                                      discoveryComplete: reading.discoveryComplete, memory: &memory, at: date)
    }

    var entries: [String: RunnerHealthMemory.Entry] { memory.entries }
}

/// RunningMan's background check: runner health from discovery, launchd and the process
/// list. It only looks: no network (server activity stays off), no Keychain, no writes,
/// no prompts. Findings become suggestions through `RunnerOfflineRule`.
struct RunnerHealthWatcher: Watcher {
    let moduleID = RunnerHealthCheck.moduleID
    /// Local reads only, so no `.network`.
    let cadence = WatchCadence(interval: WatchCadence.minimumInterval)

    let probe: any RunnerStateProbing
    let memory: RunnerHealthMemoryStore
    /// Folders the user imported in the pane; read on every check.
    let additionalDirectories: @Sendable () -> [URL]
    var now: @Sendable () -> Date = { Date() }

    func observe() async -> WatchObservation {
        // Dated when reading starts, so a stop acknowledged meanwhile is not undone by it.
        let startedAt = now()
        let reading = await probe.read(additionalDirectories: additionalDirectories())

        // A cancelled read reports every runner as unreadable; report the cancellation instead.
        guard !Task.isCancelled else {
            return .unavailable(moduleID: moduleID, at: startedAt,
                                ObservationFailure(kind: .failed, message: "The runner check was stopped before it finished."))
        }

        return await memory.observation(of: reading, at: startedAt)
    }
}
