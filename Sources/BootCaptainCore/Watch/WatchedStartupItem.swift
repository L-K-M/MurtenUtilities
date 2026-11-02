import Foundation

/// An app bundle that contains a startup item, runs its executable, or claims
/// it through `AssociatedBundleIdentifiers`.
public struct AppIdentity: Codable, Sendable, Hashable {
    /// Display name, e.g. "Docker" for `Docker.app`.
    public var name: String
    public var bundleIdentifier: String?

    public init(name: String, bundleIdentifier: String? = nil) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }
}

/// A startup item as the suite's background check sees it: enough to compare
/// it with the inventory the user last reviewed and to name the product that
/// added it. `id` uses the scan's identity (`<mechanism>:<label>`, as
/// `LaunchdFileCollector` builds it), so the two compare directly.
public struct WatchedStartupItem: Codable, Sendable, Equatable {
    public var id: String
    public var mechanism: Mechanism
    public var label: String
    public var sourcePath: String
    /// The app the plist lives in or whose executable it runs, when known.
    public var owningApp: AppIdentity?
    /// `AssociatedBundleIdentifiers` from the plist: the app that claims it.
    public var associatedBundleIdentifiers: [String]

    public init(
        id: String,
        mechanism: Mechanism,
        label: String,
        sourcePath: String,
        owningApp: AppIdentity? = nil,
        associatedBundleIdentifiers: [String] = []
    ) {
        self.id = id
        self.mechanism = mechanism
        self.label = label
        self.sourcePath = sourcePath
        self.owningApp = owningApp
        self.associatedBundleIdentifiers = associatedBundleIdentifiers
    }
}
