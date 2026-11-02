import Foundation

/// Carries the standalone RepoMen's settings into the suite once, so its users
/// keep their scan folders, exclusions, rules and watched folders. The suite
/// gives RepoMen its own defaults domain, so nothing is shared afterwards and the
/// standalone app's domain is only read, never changed.
///
/// Never imported: the global `watchAutoTrash` switch (auto-trash is armed per
/// folder in the suite and starts disarmed), the menu-bar, login-item and update
/// settings the suite owns, and the standalone app's last run records.
enum StandalonePreferencesImport {
    static let standaloneBundleID = "ch.lkmc.RepoMen"
    static let markerKey = "importedStandalonePreferences"

    /// The keys copied as they are. `watchedFolders` decodes unarmed: its JSON
    /// has no arming field.
    static let importedKeys = [
        "scanRoots", "excludedPaths", "moveToTrash", "idleDays", "disabledKinds",
        "lifetimeReclaimedBytes", "lifetimeReclaimedCount", "watchedFolders", "scanAtLaunch",
    ]

    /// The standalone app's own domain, exactly: no search list, so neither the
    /// global domain nor the suite's values can masquerade as imported ones.
    static func standaloneValues() -> [String: Any]? {
        UserDefaults.standard.persistentDomain(forName: standaloneBundleID)
    }

    /// Copies each imported key the suite does not have yet, then records that
    /// the import ran, so a later change in either app is never copied over.
    static func importOnce(from standalone: [String: Any], into suite: UserDefaults) {
        guard !suite.bool(forKey: markerKey) else { return }
        for key in importedKeys where suite.object(forKey: key) == nil {
            guard let value = standalone[key] else { continue }
            suite.set(value, forKey: key)
        }
        suite.set(true, forKey: markerKey)
    }
}
