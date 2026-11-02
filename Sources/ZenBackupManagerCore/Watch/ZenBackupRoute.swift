import Foundation

/// Identifiers the provider, the watcher and the rule share.
public enum ZenBackupRoute {
    /// Matches the descriptor in `ModuleRegistry`.
    public static let moduleID = "zenbackupmanager"
    /// Opens the timeline. The pane re-scans and selects no backup to restore.
    public static let timelineAction = "timeline"
    /// The profile's directory path (`ZenProfile.id`) the timeline opens on.
    public static let profileKey = "profile"
}
