import Foundation

@MainActor
protocol ApplicationLifecycleManaging: AnyObject {
    func runningProcesses(matching clients: Set<String>) async throws -> [AffectedProcess]
    func requestTermination(of processes: [AffectedProcess])
    func forceTerminate(_ process: AffectedProcess) throws
}

extension ApplicationLifecycleManaging {
    func forceTerminate(_ process: AffectedProcess) throws {
        throw ProcessTerminationError.unavailable
    }
}
