import Foundation

/// What a program-list file records about one program: the fields the Add
/// Program dialog collects, and nothing derived from them.
public struct ExportedApp: Codable, Equatable, Sendable {
    public var name: String
    /// Always written by an export. On import it may be left out to have the
    /// forge detected from the URL, as "Detect automatically" does.
    public var sourceType: SourceType?
    public var sourceURL: String
    /// The program of a multi-program release; absent for the usual
    /// repository with one program per release.
    public var assetFilter: String?
    public var username: String?
    /// Never written, so a shared file carries no secret, but accepted on
    /// import so a hand-edited file can restore a private instance in one go.
    /// Honoured only for a forge that authenticates with it.
    public var accessToken: String?
    /// The suite's optional identity hint; older readers ignore it.
    public var bundleID: String?

    public init(name: String, sourceType: SourceType? = nil, sourceURL: String, assetFilter: String? = nil,
                username: String? = nil, accessToken: String? = nil, bundleID: String? = nil) {
        self.name = name
        self.sourceType = sourceType
        self.sourceURL = sourceURL
        self.assetFilter = assetFilter
        self.username = username
        self.accessToken = accessToken
        self.bundleID = bundleID
    }

    init(_ app: TrackedApp) {
        self.init(name: app.name, sourceType: app.sourceType, sourceURL: app.sourceURL,
                  assetFilter: app.assetFilter, username: app.username, bundleID: app.bundleID)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case sourceType = "source_type"
        case sourceURL = "source_url"
        case assetFilter = "asset_filter"
        case username
        case accessToken = "access_token"
        case bundleID = "bundle_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        sourceType = try container.decodeIfPresent(SourceType.self, forKey: .sourceType)
        sourceURL = try container.decode(String.self, forKey: .sourceURL)
        assetFilter = try container.decodeIfPresent(String.self, forKey: .assetFilter)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
    }

    /// Writes everything but the key.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(sourceType, forKey: .sourceType)
        try container.encode(sourceURL, forKey: .sourceURL)
        try container.encodeIfPresent(assetFilter, forKey: .assetFilter)
        try container.encodeIfPresent(username, forKey: .username)
        try container.encodeIfPresent(bundleID, forKey: .bundleID)
    }
}
