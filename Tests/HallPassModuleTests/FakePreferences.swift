import Foundation
import HallPassCore
@testable import HallPassModule

/// Stands in for the osascript service: no administrator prompt, no
/// system preferences. Saves echo the desired configuration unless the
/// test scripts a failure; `holdCalls` parks calls until `release()`.
actor FakePreferences: PreferencesServicing {
    private let baseline: PreferencesSnapshot
    private let saveFailure: PreferencesServiceError?
    private let holdCalls: Bool
    private var parked: CheckedContinuation<Void, Never>?
    private(set) var loads = 0
    private(set) var saves: [NetworkConfiguration] = []

    init(baseline: NetworkConfiguration, saveFailure: PreferencesServiceError? = nil, holdCalls: Bool = false) throws {
        self.baseline = try PreferencesSnapshot(configuration: baseline)
        self.saveFailure = saveFailure
        self.holdCalls = holdCalls
    }

    /// Returns once a call is parked; gives up after five seconds so a
    /// broken test fails instead of hanging.
    func waitForParkedCall() async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while parked == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return parked != nil
    }

    func release() {
        parked?.resume()
        parked = nil
    }

    func load() async throws -> PreferencesSnapshot {
        loads += 1
        await hold()
        return baseline
    }

    func save(_ plan: PreferencePlan) async throws -> PreferencesSnapshot {
        saves.append(plan.desired)
        await hold()
        if let saveFailure { throw saveFailure }
        return try PreferencesSnapshot(configuration: plan.desired)
    }

    private func hold() async {
        guard holdCalls else { return }
        // One parked call at a time: a second would orphan the first
        // continuation and hang the suite instead of failing it.
        precondition(parked == nil, "FakePreferences parks one call at a time")
        await withCheckedContinuation { parked = $0 }
    }
}

/// A throwaway defaults domain and HallPass folder per test.
@MainActor
struct Sandbox {
    let suiteName: String
    let defaults: UserDefaults
    let root: URL

    init() {
        suiteName = "HallPassModuleTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HallPassModuleTests-\(UUID().uuidString)", isDirectory: true)
    }

    func model(_ service: FakePreferences, mode: SessionMode = .system) -> HallPassModel {
        HallPassModel(defaults: defaults, mode: mode, backups: BackupStore(root: root), service: service)
    }

    func backupFiles() throws -> [URL] {
        let backups = root.appendingPathComponent("Backups", isDirectory: true)
        guard FileManager.default.fileExists(atPath: backups.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }
}
