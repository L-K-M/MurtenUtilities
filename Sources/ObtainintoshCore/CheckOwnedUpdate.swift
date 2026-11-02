import Foundation

/// The fields a completed check owns. Deliberately narrow: a check has no
/// business writing the name, source or credentials, so it cannot clobber an
/// edit the user made while it ran.
public struct CheckOwnedUpdate: Equatable, Sendable {
    public var currentVersion: String?
    public var installPath: String?
    public var latestVersion: String?
    public var attempt: CheckAttempt

    public init(currentVersion: String?, installPath: String?, latestVersion: String?, attempt: CheckAttempt) {
        self.currentVersion = currentVersion
        self.installPath = installPath
        self.latestVersion = latestVersion
        self.attempt = attempt
    }

    /// The update a lookup result makes. The installed-version detection is
    /// fresh either way, so it is written even when the lookup failed; a
    /// failure must not move `latestVersion` or `lastChecked`.
    public static func from(installed: InstalledVersion?, sourceType: SourceType,
                            result: Result<Release, Error>, attemptedAt: String) -> CheckOwnedUpdate {
        switch result {
        case .success(let release):
            return CheckOwnedUpdate(currentVersion: installed?.version, installPath: installed?.path,
                                    latestVersion: release.version, attempt: .succeeded(at: attemptedAt))
        case .failure(let error):
            let state: CheckAttemptState = sourceType == .gitlab ? .unsupported : .failed
            return CheckOwnedUpdate(currentVersion: installed?.version, installPath: installed?.path,
                                    latestVersion: nil,
                                    attempt: .unsuccessful(at: attemptedAt, state: state,
                                                           message: error.localizedDescription))
        }
    }
}
