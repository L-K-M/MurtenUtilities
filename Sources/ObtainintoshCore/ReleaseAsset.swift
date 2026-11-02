import Foundation

/// A downloadable file of a release, as both forges report it, or a font
/// file committed to a repository standing in for one.
public struct ReleaseAsset: Decodable, NamedAsset, Equatable, Sendable {
    public var name: String
    public var browserDownloadURL: String
    public var size: UInt64

    public init(name: String, browserDownloadURL: String, size: UInt64) {
        self.name = name
        self.browserDownloadURL = browserDownloadURL
        self.size = size
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
    }
}
