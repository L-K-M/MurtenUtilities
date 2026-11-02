import Foundation

/// The status column of a tracked program, decided exactly as the standalone
/// app's table row did.
public enum ProgramStatus: Equatable, Sendable {
    case unsupported(help: String)
    /// The last check failed; `stale` when an earlier latest version is
    /// still shown beside it.
    case checkFailed(stale: Bool, help: String)
    case updateAvailable
    case notChecked
    case notFound
    case upToDate
    case notInstalled

    public init(_ app: TrackedApp) {
        if app.lastCheckAttempt?.state == .unsupported {
            self = .unsupported(help: Self.nonEmpty(app.lastCheckAttempt?.message)
                ?? "This source cannot be checked for updates.")
        } else if app.lastCheckAttempt?.state == .failed {
            self = .checkFailed(stale: Self.nonEmpty(app.latestVersion) != nil, help: Self.failedCheckHelp(app))
        } else if VersionComparison.hasUpdate(current: app.currentVersion, latest: app.latestVersion) {
            self = .updateAvailable
        } else if Self.nonEmpty(app.lastChecked) == nil {
            self = .notChecked
        } else if Self.nonEmpty(app.latestVersion) == nil {
            self = .notFound
        } else if Self.nonEmpty(app.currentVersion) != nil {
            self = .upToDate
        } else {
            self = .notInstalled
        }
    }

    public var label: String {
        switch self {
        case .unsupported: return "Unsupported"
        case .checkFailed(let stale, _): return stale ? "Check Failed (Stale)" : "Check Failed"
        case .updateAvailable: return "Update Available"
        case .notChecked: return "Not Checked"
        case .notFound: return "Not Found"
        case .upToDate: return "Up to Date"
        case .notInstalled: return "Not Installed"
        }
    }

    /// The balloon help the row showed, if any.
    public var help: String? {
        switch self {
        case .unsupported(let help), .checkFailed(_, let help): return help
        case .notChecked: return "This program hasn't been checked for updates yet."
        case .notFound: return "No version of this application compatible with this computer was found."
        case .updateAvailable, .upToDate, .notInstalled: return nil
        }
    }

    /// Whether the row shows the alert icon.
    public var isAlert: Bool {
        switch self {
        case .unsupported, .checkFailed, .notFound: return true
        case .updateAvailable, .notChecked, .upToDate, .notInstalled: return false
        }
    }

    /// A failed check leaves any previously known latest version in place,
    /// so the help has to say that the figure beside it is older.
    static func failedCheckHelp(_ app: TrackedApp) -> String {
        let message = nonEmpty(app.lastCheckAttempt?.message) ?? "The update check did not complete."
        if nonEmpty(app.latestVersion) != nil {
            return "Last update check failed: \(message) The latest version shown is from an earlier successful check."
        }
        return "Last update check failed: \(message)"
    }

    static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }
}
