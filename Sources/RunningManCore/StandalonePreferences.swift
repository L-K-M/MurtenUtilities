import Foundation

/// The standalone app's preferences the suite module can take over once, with the
/// user's consent: the runner folders imported there and its Forgejo server list.
/// The suite has its own preferences domain, so without this they would silently
/// start empty (docs/architecture.md, Transition from the standalone apps).
///
/// Only the module's store is ever written; the standalone domain is read, never
/// changed, so the standalone app keeps working as before. Forgejo tokens stay in
/// the Keychain and launchd labels stay as they are, both read in place.
public struct StandalonePreferences: Equatable, Sendable {
    /// The standalone app's bundle identifier, which names its preferences domain.
    public static let domain = "ch.lkmc.RunningMan"
    /// Set in the module's store once the user imported or declined.
    public static let decisionKey = "standalonePreferencesImport"
    /// Bounds what is copied from another app's file.
    static let maximumEntries = 256

    public enum Key {
        public static let runnerDirectories = "importedRunnerDirectories"
        public static let forgejoServers = "forgejoServers"
        public static let defaultForgejoServer = "defaultForgejoServer"
    }

    public enum Decision: String, Sendable {
        case imported, declined
    }

    /// Absolute folder paths, in the standalone app's order.
    public var runnerDirectories: [String]
    /// HTTPS server origins, in the standalone app's order.
    public var forgejoServers: [String]
    public var defaultForgejoServer: String?

    public var isEmpty: Bool { runnerDirectories.isEmpty && forgejoServers.isEmpty }

    public init(runnerDirectories: [String] = [], forgejoServers: [String] = [], defaultForgejoServer: String? = nil) {
        self.runnerDirectories = runnerDirectories
        self.forgejoServers = forgejoServers
        self.defaultForgejoServer = defaultForgejoServer
    }

    /// What the standalone domain holds, keeping only absolute paths and HTTPS
    /// servers without credentials.
    public static func read(from standalone: UserDefaults) -> StandalonePreferences {
        let directories = unique(standalone.stringArray(forKey: Key.runnerDirectories) ?? []) { $0.hasPrefix("/") }
        let servers = unique(standalone.stringArray(forKey: Key.forgejoServers) ?? [], where: isServer)
        let fallback = standalone.string(forKey: Key.defaultForgejoServer)
        return StandalonePreferences(runnerDirectories: directories, forgejoServers: servers,
                                     defaultForgejoServer: fallback.flatMap { servers.contains($0) ? $0 : nil })
    }

    /// The import to offer: the standalone app has folders or servers, the module's
    /// own store has neither, and the user has not answered yet. Nil otherwise.
    public static func offer(standalone: UserDefaults?, module: UserDefaults) -> StandalonePreferences? {
        guard let standalone, module.string(forKey: decisionKey) == nil,
              (module.stringArray(forKey: Key.runnerDirectories) ?? []).isEmpty,
              (module.stringArray(forKey: Key.forgejoServers) ?? []).isEmpty else { return nil }
        let found = read(from: standalone)
        return found.isEmpty ? nil : found
    }

    /// Adds these values to the module's store, after anything already there, and
    /// records the decision so the offer does not come back.
    public func apply(to module: UserDefaults) {
        let directories = Self.unique((module.stringArray(forKey: Key.runnerDirectories) ?? []) + runnerDirectories) { _ in true }
        let servers = Self.unique((module.stringArray(forKey: Key.forgejoServers) ?? []) + forgejoServers) { _ in true }
        module.set(directories, forKey: Key.runnerDirectories)
        module.set(servers, forKey: Key.forgejoServers)
        if module.string(forKey: Key.defaultForgejoServer) == nil, let fallback = defaultForgejoServer ?? servers.first {
            module.set(fallback, forKey: Key.defaultForgejoServer)
        }
        module.set(Decision.imported.rawValue, forKey: Self.decisionKey)
    }

    /// The user does not want the standalone values; the offer does not come back.
    public static func decline(in module: UserDefaults) {
        module.set(Decision.declined.rawValue, forKey: decisionKey)
    }

    private static func isServer(_ text: String) -> Bool {
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", url.host != nil else { return false }
        return url.user == nil && url.password == nil
    }

    private static func unique(_ values: [String], where isAcceptable: (String) -> Bool) -> [String] {
        var seen = Set<String>()
        return Array(values.filter { isAcceptable($0) && seen.insert($0).inserted }.prefix(maximumEntries))
    }
}
