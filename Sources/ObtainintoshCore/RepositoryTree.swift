import Foundation

/// A forge's recursive listing of a repository's files. GitHub and Forgejo
/// name these fields alike. Only Forgejo pages the listing and counts it;
/// only GitHub's `truncated` means the listing stops short (Forgejo sets it
/// on every page of a paged listing).
public struct RepositoryTree: Decodable, Sendable {
    public struct Entry: Decodable, Equatable, Sendable {
        public static let fileKind = "blob"

        public var path: String
        public var kind: String
        public var size: UInt64

        public init(path: String, kind: String, size: UInt64) {
            self.path = path
            self.kind = kind
            self.size = size
        }

        private enum CodingKeys: String, CodingKey {
            case path
            case kind = "type"
            case size
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            path = try container.decode(String.self, forKey: .path)
            kind = try container.decode(String.self, forKey: .kind)
            size = try container.decodeIfPresent(UInt64.self, forKey: .size) ?? 0
        }
    }

    public var tree: [Entry]
    public var totalCount: Int?
    public var truncated: Bool

    private enum CodingKeys: String, CodingKey {
        case tree
        case totalCount = "total_count"
        case truncated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tree = try container.decode([Entry].self, forKey: .tree)
        totalCount = try container.decodeIfPresent(Int.self, forKey: .totalCount)
        truncated = try container.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
    }
}
