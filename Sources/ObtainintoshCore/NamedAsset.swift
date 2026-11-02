import Foundation

/// Anything with a file name the picker can rank: release assets, files
/// committed to a repository.
public protocol NamedAsset {
    var name: String { get }
}
