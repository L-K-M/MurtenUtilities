import Foundation

/// Where one download writes. The cache is shared per program and version,
/// so a re-download replaces the older copy instead of piling up duplicates,
/// and "this version is downloaded" is one existence check on a path that
/// can be recomputed from the program alone.
public struct DownloadLayout: Equatable, Sendable {
    /// The directory below the system's temporary directory, shared with
    /// the standalone app so a file either app downloaded can be revealed.
    public static let cacheDirectoryName = "obtainintosh-downloads"

    public let directory: URL
    public let partial: URL
    public let completed: URL

    /// Asset names and version tags come from the forge API, so each is
    /// reduced to one safe path component and nothing can escape `root`.
    public init(root: URL, appKey: String, version: String, fileName: String) throws {
        let name = (fileName as NSString).lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", name != "/" else {
            throw ObtainintoshError("Invalid asset file name")
        }
        directory = root.appendingPathComponent(Self.safePathComponent(appKey), isDirectory: true)
            .appendingPathComponent(Self.safePathComponent(version), isDirectory: true)
        partial = directory.appendingPathComponent(name + ".part")
        completed = directory.appendingPathComponent(name)
    }

    /// One piece of forge-supplied text as a single safe path component: the
    /// final component of whatever arrived (so `../` cannot traverse), with
    /// characters outside `[A-Za-z0-9._-]` folded to `_`. Empty becomes `_`.
    public static func safePathComponent(_ component: String) -> String {
        let last = component.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? ""
        let name = (last == "." || last == "..") ? "" : last
        let folded = String(name.map { character -> Character in
            character.isASCIIAlphanumeric || character == "." || character == "_" || character == "-" ? character : "_"
        })
        return folded.isEmpty ? "_" : folded
    }

    /// A download is valid only at exactly the size the forge reported.
    public static func validateSize(_ actual: UInt64, expected: UInt64) throws {
        guard actual == expected else {
            throw ObtainintoshError("Downloaded \(actual) bytes, but the forge reported an asset size of \(expected)")
        }
    }
}
