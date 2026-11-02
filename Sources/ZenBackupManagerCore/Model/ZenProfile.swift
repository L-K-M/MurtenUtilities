import Foundation

public struct ZenProfile: Identifiable, Hashable, Sendable {
    public let name: String
    public let directory: URL
    public let isDefault: Bool
    public var id: String { directory.path }

    public init(name: String, directory: URL, isDefault: Bool) {
        self.name = name
        self.directory = directory
        self.isDefault = isDefault
    }
}
