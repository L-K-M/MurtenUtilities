import Foundation

/// The whole data file: the standalone app's `apps.json` shape, plus the
/// suite's tombstones of removed entries.
public struct TrackedAppData: Codable, Equatable, Sendable {
    /// How many removed entry ids are remembered for the background check.
    public static let removedIDLimit = 100

    public var apps: [TrackedApp]
    /// The standalone app keeps its GitHub token here in plain text. The
    /// suite reads it once on import and keeps tokens in the Keychain.
    public var settings: StoredSettings
    /// The standalone app's one-shot marker for its self-entry; read and
    /// written back unchanged.
    public var selfEntrySeeded: Bool
    /// Ids of entries the user removed, newest last. The background check
    /// reports them as checked, so a suggestion for a removed program
    /// resolves instead of lingering.
    public var removedAppIDs: [String]

    public init(apps: [TrackedApp] = [], settings: StoredSettings = StoredSettings(),
                selfEntrySeeded: Bool = false, removedAppIDs: [String] = []) {
        self.apps = apps
        self.settings = settings
        self.selfEntrySeeded = selfEntrySeeded
        self.removedAppIDs = removedAppIDs
    }

    private enum CodingKeys: String, CodingKey {
        case apps, settings
        case selfEntrySeeded = "self_entry_seeded"
        case removedAppIDs = "removed_app_ids"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apps = try container.decode([TrackedApp].self, forKey: .apps)
        settings = try container.decodeIfPresent(StoredSettings.self, forKey: .settings) ?? StoredSettings()
        selfEntrySeeded = try container.decodeIfPresent(Bool.self, forKey: .selfEntrySeeded) ?? false
        removedAppIDs = try container.decodeIfPresent([String].self, forKey: .removedAppIDs) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(apps, forKey: .apps)
        try container.encode(settings, forKey: .settings)
        try container.encode(selfEntrySeeded, forKey: .selfEntrySeeded)
        if !removedAppIDs.isEmpty { try container.encode(removedAppIDs, forKey: .removedAppIDs) }
    }

    /// The same data with every secret removed, as the suite writes it.
    public var withoutSecrets: TrackedAppData {
        var copy = self
        copy.apps = apps.map(\.withoutAccessToken)
        copy.settings = StoredSettings()
        return copy
    }
}

/// The standalone app's settings block.
public struct StoredSettings: Codable, Equatable, Sendable {
    public var githubToken: String?
    public var gitlabToken: String?

    public init(githubToken: String? = nil, gitlabToken: String? = nil) {
        self.githubToken = githubToken
        self.gitlabToken = gitlabToken
    }

    private enum CodingKeys: String, CodingKey {
        case githubToken = "github_token"
        case gitlabToken = "gitlab_token"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        githubToken = try container.decodeIfPresent(String.self, forKey: .githubToken)
        gitlabToken = try container.decodeIfPresent(String.self, forKey: .gitlabToken)
    }

    /// The standalone shape, with both tokens always null: they are read
    /// from the standalone app's file but never written anywhere.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNil(forKey: .githubToken)
        try container.encodeNil(forKey: .gitlabToken)
    }
}
