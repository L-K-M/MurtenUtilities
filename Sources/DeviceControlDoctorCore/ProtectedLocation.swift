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

    /// Where `path` really leads, or nil when it is, or passes through, a
    /// guarded location. A symlink placed after the app was added (the app
    /// itself, or `~/Applications` pointing into Documents) would otherwise
    /// lead a background read into a guarded folder.
    ///
    /// Links are resolved one component at a time with `linkDestination`
    /// (an `lstat` plus `readlink` of that one entry), and the walk stops
    /// before it would look at anything inside a guarded location, so the
    /// resolution itself cannot prompt. The home folder is the one guarded
    /// path the walk may pass, because the safe folders sit inside it.
    public static func readablePath(_ path: String, home: String,
                                    linkDestination: (String) -> String?) -> String? {
        let home = normalized(home)
        var components = lexicalComponents(of: path)
        var resolved = ""
        var index = 0
        var hops = 0

        while index < components.count {
            let candidate = resolved + "/" + components[index]
            if candidate != home && contains(candidate, home: home) { return nil }

            guard let destination = linkDestination(candidate) else {
                resolved = candidate
                index += 1
                continue
            }

            hops += 1
            guard hops <= maximumLinkHops else { return nil }
            // A relative target is relative to the link's folder, which is
            // already free of links, so lexical ".." handling is exact.
            let base = destination.hasPrefix("/") ? destination : resolved + "/" + destination
            components = lexicalComponents(of: ([base] + components[(index + 1)...]).joined(separator: "/"))
            resolved = ""
            index = 0
        }
        return resolved.isEmpty ? "/" : resolved
    }

    /// The kernel's own limit (MAXSYMLINKS) is 32.
    private static let maximumLinkHops = 32

    private static func lexicalComponents(of path: String) -> [String] {
        var components: [String] = []
        for component in path.split(separator: "/") where component != "." {
            if component == ".." {
                _ = components.popLast()
            } else {
                components.append(String(component))
            }
        }
        return components
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
