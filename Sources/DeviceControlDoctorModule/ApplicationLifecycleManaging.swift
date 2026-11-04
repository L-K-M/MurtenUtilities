import Foundation

@MainActor
protocol ApplicationLifecycleManaging: AnyObject {
    func runningProcesses(matching clients: Set<String>) async throws -> [AffectedProcess]
    func requestTermination(of processes: [AffectedProcess])
}
