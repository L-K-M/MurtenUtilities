import Foundation

@MainActor
protocol ProcessForceTerminating {
    /// A successful request is not proof of exit. The next inventory confirms
    /// that the process is gone, or exposes a helper that has relaunched.
    func forceTerminate(_ process: AffectedProcess) throws
}
