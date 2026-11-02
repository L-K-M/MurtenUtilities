import Foundation

/// A release resolved for this Mac: the asset to download and its version.
public struct Release: Equatable, Sendable {
    public var version: String
    public var downloadURL: String
    public var fileName: String
    public var fileSize: UInt64?
    public var releaseNotes: String?

    public init(version: String, downloadURL: String, fileName: String, fileSize: UInt64?,
                releaseNotes: String? = nil) {
        self.version = version
        self.downloadURL = downloadURL
        self.fileName = fileName
        self.fileSize = fileSize
        self.releaseNotes = releaseNotes
    }
}

/// The programs a release offers this Mac, for the Add Program dialog to
/// offer when a repository publishes several.
public struct ReleasePrograms: Equatable, Sendable {
    public var version: String
    /// Sorted program names, e.g. `["planchette", "poltergeist", "seance"]`.
    public var programs: [String]
    /// The program an entry without a filter downloads.
    public var defaultProgram: String?

    public init(version: String, programs: [String], defaultProgram: String?) {
        self.version = version
        self.programs = programs
        self.defaultProgram = defaultProgram
    }
}
