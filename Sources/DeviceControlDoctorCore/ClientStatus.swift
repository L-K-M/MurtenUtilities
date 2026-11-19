import Foundation

/// What the module found out about a permission client on this Mac. The
/// module gathers it (LaunchServices, the file system); the rules that turn
/// it into flags live here so they can be tested without either.
public struct ClientStatus: Hashable, Sendable {
    public enum Presence: Hashable, Sendable {
        /// A copy outside the Trash.
        case installed(path: String)
        /// Only a copy in a Trash. `tccutil` may still find it.
        case inTrash(path: String)
        /// On a volume that is not connected now.
        case offline(path: String)
        case missing

        public var path: String? {
            switch self {
            case .installed(let path), .inTrash(let path), .offline(let path): return path
            case .missing: return nil
            }
        }
    }

    /// The name people see: the app's display name, else the file name,
    /// else the identifier.
    public var name: String
    public var presence: Presence
    /// Part of macOS. Never offered for reset or flagged as a leftover.
    public var isSystem: Bool
    /// The bundle identifier of the app it belongs to: its own for a bundle
    /// client, the enclosing app's for an executable inside one.
    public var appIdentifier: String?

    public init(name: String, presence: Presence, isSystem: Bool, appIdentifier: String? = nil) {
        self.name = name
        self.presence = presence
        self.isSystem = isSystem
        self.appIdentifier = appIdentifier
    }

    // MARK: - Presence

    /// Classifies the copies LaunchServices or the record names.
    /// `exists` answers for a path; a copy under `/Volumes/<name>` whose
    /// volume is not mounted is offline rather than gone.
    public static func presence(of paths: [String], home: String, exists: (String) -> Bool) -> Presence {
        let present = paths.filter(exists)
        if let installed = present.first(where: { !isInTrash($0, home: home) }) { return .installed(path: installed) }
        if let trashed = present.first { return .inTrash(path: trashed) }
        if let offline = paths.first(where: { path in
            guard let volume = volumeRoot(of: path) else { return false }
            return !exists(volume)
        }) {
            return .offline(path: offline)
        }
        return .missing
    }

    /// `~/.Trash`, any account's `/Users/<name>/.Trash` (the system
    /// database holds every account's decisions), and the `.Trashes`
    /// folder at the root of any volume.
    public static func isInTrash(_ path: String, home: String) -> Bool {
        let home = home.hasSuffix("/") ? String(home.dropLast()) : home
        if path.hasPrefix(home + "/.Trash/") || path.hasPrefix("/.Trashes/") { return true }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        if path.hasPrefix("/Users/"), parts.count > 3, parts[2] == ".Trash" { return true }
        guard let volume = volumeRoot(of: path) else { return false }
        return path.hasPrefix(volume + "/.Trashes/")
    }

    /// `/Volumes/<name>` for a path below it, else nil.
    public static func volumeRoot(of path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard path.hasPrefix("/Volumes/"), parts.count >= 3 else { return nil }
        return "/Volumes/" + parts[1]
    }

    // MARK: - System clients

    /// Folders only macOS installs into. `/usr/local` is the user's.
    static let systemRoots = ["/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/"]

    /// A client is part of macOS when it lives in a system folder, or when
    /// it is Apple's (`com.apple.`) and no copy outside a system folder
    /// exists: Apple's daemons have no app bundle for LaunchServices to
    /// find. Xcode in /Applications is Apple's but not part of macOS.
    public static func isSystem(client: String, kind: PermissionRecord.ClientKind, presence: Presence) -> Bool {
        if let path = kind == .path ? client : presence.path, isSystemPath(path) { return true }
        guard kind == .bundleIdentifier, client.hasPrefix("com.apple.") else { return false }
        switch presence {
        case .installed, .inTrash, .offline: return false
        case .missing: return true
        }
    }

    public static func isSystemPath(_ path: String) -> Bool {
        if path.hasPrefix("/usr/local/") { return false }
        return systemRoots.contains { path.hasPrefix($0) }
    }

    /// The `.app` bundle that contains an executable path, if any:
    /// "/Applications/Foo.app/Contents/MacOS/foo" → "/Applications/Foo.app".
    public static func enclosingAppPath(of path: String) -> String? {
        guard let range = path.range(of: ".app/", options: .backwards) else {
            return path.hasSuffix(".app") ? path : nil
        }
        return String(path[..<range.lowerBound]) + ".app"
    }
}
