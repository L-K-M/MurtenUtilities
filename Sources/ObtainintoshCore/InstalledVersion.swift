import Foundation

/// Where a program or font is installed and the version it declares.
public struct InstalledVersion: Equatable, Sendable {
    public var path: String
    public var version: String

    public init(path: String, version: String) {
        self.path = path
        self.version = version
    }
}
