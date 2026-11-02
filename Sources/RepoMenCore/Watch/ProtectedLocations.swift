import Foundation

/// Folders macOS guards with a privacy prompt: Desktop, Documents and Downloads
/// (Files and Folders), iCloud Drive, File Provider storage, and removable or
/// network volumes. Work nobody started by hand (the suite's background check,
/// armed auto-trash) never reads inside them, because a prompt with no window in
/// front is exactly what the suite promises not to show. The pane scans them on
/// demand, where the prompt answers the user's own click.
package enum ProtectedLocations {

    /// The protected roots for `home`. The Data-volume spellings reach the same
    /// folders through the firmlink, so they are protected too.
    package static func roots(home: String) -> [String] {
        let home = home.hasSuffix("/") ? String(home.dropLast()) : home
        let inHome = ["Desktop", "Documents", "Downloads",
                      "Library/Mobile Documents", "Library/CloudStorage"]
            .map { home + "/" + $0 }
        return inHome + inHome.map { dataVolume + $0 } + ["/Volumes"]
    }

    private static let dataVolume = "/System/Volumes/Data"

    /// The live roots for the current user.
    package static var current: [String] {
        roots(home: FileManager.default.homeDirectoryForCurrentUser.path)
    }

    /// Lexical check, folding case like APFS does by default: true when `path` is
    /// one of `roots` or lies below one. Never touches the file system.
    package static func contains(_ path: String, roots: [String]) -> Bool {
        let folded = path.lowercased()
        return roots.contains { root in
            let foldedRoot = root.lowercased()
            return folded == foldedRoot || folded.hasPrefix(foldedRoot + "/")
        }
    }

    package enum Classification: Equatable, Sendable {
        /// Resolves outside every protected root.
        case allowed
        /// Lies in, or resolves through a symbolic link into, this protected root.
        case protected(root: String)
        /// Too many symbolic links to follow.
        case unresolvable
    }

    /// Follows `path` one component at a time, symbolic links included, and stops
    /// at the first protected prefix, before anything inside it is looked at.
    /// `readLink` returns a link's destination, or nil for anything else; only
    /// prefixes already known to be outside the protected roots are passed to it.
    package static func classify(_ path: String, roots: [String],
                                 readLink: (String) -> String? = liveReadLink) -> Classification {
        // As written first: a path spelled inside a root is protected whatever
        // its links would resolve to.
        if let root = protectedRoot(of: lexicallyNormalized(path), roots: roots) {
            return .protected(root: root)
        }

        var pending = components(of: path)
        var resolved: [String] = []
        var hops = 0

        while !pending.isEmpty {
            let next = pending.removeFirst()
            if next == "." { continue }
            if next == ".." {
                _ = resolved.popLast()
                continue
            }

            let candidate = "/" + (resolved + [next]).joined(separator: "/")
            if let root = protectedRoot(of: candidate, roots: roots) {
                return .protected(root: root)
            }

            guard let destination = readLink(candidate) else {
                resolved.append(next)
                continue
            }
            hops += 1
            guard hops <= maximumLinkHops else { return .unresolvable }
            if destination.hasPrefix("/") { resolved = [] }
            pending = components(of: destination) + pending
        }

        let final = "/" + resolved.joined(separator: "/")
        if let root = protectedRoot(of: final, roots: roots) { return .protected(root: root) }
        return .allowed
    }

    /// The same limit as the kernel's MAXSYMLINKS.
    private static let maximumLinkHops = 32

    /// Folds `.` and `..` without touching the file system. Unlike
    /// `standardizedFileURL`, it keeps a `/private` prefix, so the result can be
    /// compared with the roots as given.
    package static func lexicallyNormalized(_ path: String) -> String {
        var result: [String] = []
        for component in components(of: path) {
            switch component {
            case ".": continue
            case "..": _ = result.popLast()
            default: result.append(component)
            }
        }
        return "/" + result.joined(separator: "/")
    }

    package static func liveReadLink(_ path: String) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: path)
    }

    private static func protectedRoot(of path: String, roots: [String]) -> String? {
        roots.first { contains(path, roots: [$0]) }
    }

    private static func components(of path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }
}
