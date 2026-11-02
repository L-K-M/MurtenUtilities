import Foundation

/// What the Add/Edit Program dialog collects about a program.
public struct SourceInput: Equatable, Sendable {
    public var url: String
    public var name: String
    /// nil leaves the forge to be detected from the URL.
    public var sourceType: SourceType?
    public var username: String?
    public var accessToken: String?
    /// The program of a multi-program release, as typed; nil for none.
    public var assetFilter: String?
    public var bundleID: String?

    public init(url: String, name: String, sourceType: SourceType? = nil, username: String? = nil,
                accessToken: String? = nil, assetFilter: String? = nil, bundleID: String? = nil) {
        self.url = url
        self.name = name
        self.sourceType = sourceType
        self.username = username
        self.accessToken = accessToken
        self.assetFilter = assetFilter
        self.bundleID = bundleID
    }

    /// The forge the URL belongs to: the type picked in the dialog, or a
    /// guess from the URL. A private Forgejo instance can be at any host, so
    /// detection alone cannot be relied on.
    public func resolvedSourceType() throws -> SourceType {
        guard let type = sourceType ?? RepositoryURL.detectSourceType(url) else {
            throw ObtainintoshError("Unsupported source URL. Pick the source type (for example Forgejo) if the URL "
                + "is not a github.com repository.")
        }
        return type
    }

    /// Credentials for the forge that uses them, nothing for the others.
    public func credentials(for sourceType: SourceType) -> ForgeCredentials {
        ForgeCredentials.forSource(sourceType, username: username, token: accessToken)
    }

    /// A new entry for this input, without an id or installed version (the
    /// store and the detector add those). Its key stays in `accessToken`
    /// for the caller to move into the Keychain.
    public func makeApp() throws -> TrackedApp {
        let sourceType = try resolvedSourceType()
        let credentials = credentials(for: sourceType)
        return TrackedApp(name: name, sourceType: sourceType, sourceURL: url,
                          assetFilter: try AssetFilter.canonicalize(assetFilter ?? ""),
                          username: credentials.username, accessToken: credentials.token,
                          bundleID: Self.cleanBundleID(bundleID))
    }

    /// The entry after an edit. A changed repository or program is another
    /// source: the versions, the last check and any downloaded file of the
    /// old one are meaningless for it. Credentials come from the dialog every
    /// time, so clearing a field clears the stored value too.
    public func applied(to app: TrackedApp) throws -> TrackedApp {
        let assetFilter = try AssetFilter.canonicalize(self.assetFilter ?? "")
        var updated = app
        updated.name = name
        if app.sourceURL != url || app.assetFilter != assetFilter {
            updated.latestVersion = nil
            updated.lastChecked = nil
            updated.lastCheckAttempt = nil
            updated.downloaded = nil
            updated.sourceURL = url
            updated.assetFilter = assetFilter
        }
        // The dialog sends the type it displayed; detection covers an edit
        // that only changed the URL.
        updated.sourceType = try SourceInput(url: updated.sourceURL, name: name, sourceType: sourceType)
            .resolvedSourceType()
        let credentials = credentials(for: updated.sourceType)
        updated.username = credentials.username
        updated.accessToken = credentials.token
        updated.bundleID = Self.cleanBundleID(bundleID)
        return updated
    }

    private static func cleanBundleID(_ bundleID: String?) -> String? {
        guard let trimmed = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
