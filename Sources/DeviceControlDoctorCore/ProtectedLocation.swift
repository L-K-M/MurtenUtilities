import Foundation

/// Locations where reading an app bundle could raise a privacy prompt:
/// Files and Folders (Desktop, Documents, Downloads), iCloud Drive and
/// file providers, other apps' containers, and removable or network
/// volumes. A background check never prompts, so the watcher leaves apps
/// there to the pane, where the user started the work.
///
/// Inside the home folder only `~/Applications` and `~/Library` (minus its
/// guarded folders) count as safe; anything else in home is treated as
/// guarded rather than guessed at.
public enum ProtectedLocation {
    private static let safeInHome = ["Applications", "Library"]
    private static let guardedInLibrary = ["Containers", "Group Containers", "Mobile Documents", "CloudStorage"]
    private static let guardedRoots = ["/Volumes"]

    /// Whether `path` (absolute, symlinks resolved) may sit in a guarded
    /// location for a user whose home folder is `home`.
    public static func contains(_ path: String, home: String) -> Bool {
        let path = normalized(path)
        let home = normalized(home)

        if guardedRoots.contains(where: { isInside(path, $0) }) { return true }
        guard isInside(path, home) else { return false }

        let library = home + "/Library"
        if guardedInLibrary.contains(where: { isInside(path, library + "/" + $0) }) { return true }
        return !safeInHome.contains { isInside(path, home + "/" + $0) }
    }

    private static func normalized(_ path: String) -> String {
        var path = path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// True for `folder` itself and anything below it, never for a sibling
    /// that merely shares the prefix (`~/Applications2`).
    private static func isInside(_ path: String, _ folder: String) -> Bool {
        path == folder || path.hasPrefix(folder + "/")
    }
}
