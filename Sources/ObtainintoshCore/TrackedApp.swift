import Foundation

/// Stand-in printed in place of a secret, so a stray `print(app)` or `dump`
/// cannot put an application key in a log.
public let redactedSecret = "[redacted]"

/// One tracked program, in the shape of the standalone app's `apps.json`
/// (snake_case keys), so its file decodes unchanged.
///
/// The identity fields (id, name, source, URL) are required; everything else
/// is state Obtainintosh recomputes and defaults when absent, so a file
/// written by an older version stays loadable.
public struct TrackedApp: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var sourceType: SourceType
    public var sourceURL: String
    /// Which program of the repository's releases this entry tracks, in the
    /// canonical form of `AssetFilter` (`seance`, `*-gtk4-*`); nil leaves the
    /// choice to the platform picker.
    public var assetFilter: String?
    public var currentVersion: String?
    public var latestVersion: String?
    public var installPath: String?
    /// ISO 8601; moves only when a check succeeds.
    public var lastChecked: String?
    /// The most recent attempt, successful or not, so a stale
    /// `latestVersion` can be told from a current one.
    public var lastCheckAttempt: CheckAttempt?
    /// The release file a completed download left in the cache.
    public var downloaded: DownloadedRelease?
    /// Forgejo instance credentials; nil for sources that need none.
    public var username: String?
    /// In transit only: what the standalone app's file, an imported program
    /// list or the dialog carried. The suite keeps keys in the Keychain and
    /// never writes this field to its own file.
    public var accessToken: String?
    /// The installed app's bundle identifier, when the user recorded one.
    /// Preferred over the name when detecting the installed version.
    public var bundleID: String?
    /// Whether the suite's Keychain holds an application key for this entry.
    /// Lets a background check know a key exists without reading it.
    public var hasStoredAccessToken: Bool

    public init(id: String = "", name: String, sourceType: SourceType, sourceURL: String,
                assetFilter: String? = nil, currentVersion: String? = nil, latestVersion: String? = nil,
                installPath: String? = nil, lastChecked: String? = nil, lastCheckAttempt: CheckAttempt? = nil,
                downloaded: DownloadedRelease? = nil, username: String? = nil, accessToken: String? = nil,
                bundleID: String? = nil, hasStoredAccessToken: Bool = false) {
        self.id = id
        self.name = name
        self.sourceType = sourceType
        self.sourceURL = sourceURL
        self.assetFilter = assetFilter
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.installPath = installPath
        self.lastChecked = lastChecked
        self.lastCheckAttempt = lastCheckAttempt
        self.downloaded = downloaded
        self.username = username
        self.accessToken = accessToken
        self.bundleID = bundleID
        self.hasStoredAccessToken = hasStoredAccessToken
    }

    private enum CodingKeys: String, CodingKey {
        case id, name
        case sourceType = "source_type"
        case sourceURL = "source_url"
        case assetFilter = "asset_filter"
        case currentVersion = "current_version"
        case latestVersion = "latest_version"
        case installPath = "install_path"
        case lastChecked = "last_checked"
        case lastCheckAttempt = "last_check_attempt"
        case downloaded
        case username
        case accessToken = "access_token"
        case bundleID = "bundle_id"
        case hasStoredAccessToken = "access_token_in_keychain"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sourceType = try container.decode(SourceType.self, forKey: .sourceType)
        sourceURL = try container.decode(String.self, forKey: .sourceURL)
        assetFilter = try container.decodeIfPresent(String.self, forKey: .assetFilter)
        currentVersion = try container.decodeIfPresent(String.self, forKey: .currentVersion)
        latestVersion = try container.decodeIfPresent(String.self, forKey: .latestVersion)
        installPath = try container.decodeIfPresent(String.self, forKey: .installPath)
        lastChecked = try container.decodeIfPresent(String.self, forKey: .lastChecked)
        lastCheckAttempt = try container.decodeIfPresent(CheckAttempt.self, forKey: .lastCheckAttempt)
        downloaded = try container.decodeIfPresent(DownloadedRelease.self, forKey: .downloaded)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
        hasStoredAccessToken = try container.decodeIfPresent(Bool.self, forKey: .hasStoredAccessToken) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(sourceType, forKey: .sourceType)
        try container.encode(sourceURL, forKey: .sourceURL)
        try container.encodeIfPresent(assetFilter, forKey: .assetFilter)
        try container.encodeIfPresent(currentVersion, forKey: .currentVersion)
        try container.encodeIfPresent(latestVersion, forKey: .latestVersion)
        try container.encodeIfPresent(installPath, forKey: .installPath)
        try container.encodeIfPresent(lastChecked, forKey: .lastChecked)
        try container.encodeIfPresent(lastCheckAttempt, forKey: .lastCheckAttempt)
        try container.encodeIfPresent(downloaded, forKey: .downloaded)
        try container.encodeIfPresent(username, forKey: .username)
        try container.encodeIfPresent(accessToken, forKey: .accessToken)
        try container.encodeIfPresent(bundleID, forKey: .bundleID)
        if hasStoredAccessToken { try container.encode(true, forKey: .hasStoredAccessToken) }
    }

    /// The same record without the key it may carry in transit.
    public var withoutAccessToken: TrackedApp {
        var copy = self
        copy.accessToken = nil
        return copy
    }
}

// MARK: - Redaction

extension TrackedApp: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        let token = accessToken == nil ? "nil" : redactedSecret
        return "TrackedApp(id: \(id), name: \(name), sourceType: \(sourceType.rawValue), sourceURL: \(sourceURL), "
            + "assetFilter: \(assetFilter ?? "nil"), currentVersion: \(currentVersion ?? "nil"), "
            + "latestVersion: \(latestVersion ?? "nil"), username: \(username ?? "nil"), accessToken: \(token))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: [
            "id": id, "name": name, "sourceType": sourceType, "sourceURL": sourceURL,
            "assetFilter": assetFilter as Any, "currentVersion": currentVersion as Any,
            "latestVersion": latestVersion as Any, "username": username as Any,
            "accessToken": (accessToken == nil ? nil : redactedSecret) as Any,
        ])
    }
}

/// The release file a download left behind: which version and where it sits
/// in the cache. The cache is temporary, so the path may have vanished.
public struct DownloadedRelease: Codable, Equatable, Sendable {
    public var version: String
    public var path: String

    public init(version: String, path: String) {
        self.version = version
        self.path = path
    }
}
