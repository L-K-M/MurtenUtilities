import Foundation

struct ZenProfile: Identifiable, Hashable, Sendable {
    let name: String
    let directory: URL
    let isDefault: Bool
    var id: String { directory.path }
}
