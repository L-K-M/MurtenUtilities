import Foundation

/// The download-side button of a row, as the standalone app chose it.
public enum ProgramAction: Equatable, Sendable {
    /// The latest version's file is in the cache already: show it in Finder.
    case revealDownload
    /// Download and save the update.
    case downloadUpdate
    /// Not installed: download the program.
    case download
    case none

    public init(_ app: TrackedApp) {
        // The cached file stands in for the download button only while it
        // matches the release the program would fetch.
        if let downloaded = app.downloaded, downloaded.version == app.latestVersion {
            self = .revealDownload
        } else if VersionComparison.hasUpdate(current: app.currentVersion, latest: app.latestVersion) {
            self = .downloadUpdate
        } else if ProgramStatus.nonEmpty(app.currentVersion) == nil {
            self = .download
        } else {
            self = .none
        }
    }

    public var help: String? {
        switch self {
        case .revealDownload: return "This version's file is already downloaded — show it in Finder"
        case .downloadUpdate: return "Download and save the update for this program"
        case .download: return "Download this program"
        case .none: return nil
        }
    }
}
