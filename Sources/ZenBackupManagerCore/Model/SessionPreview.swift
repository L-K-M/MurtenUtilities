import Foundation

public struct SessionPreview: Sendable {
    public enum Format: String, Sendable { case zen = "Zen session", firefox = "Legacy session" }
    public struct Tab: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let url: String
        public let spaceID: String?
        public let pinned: Bool
        public let essential: Bool
        public var host: String { URL(string: url)?.host ?? url }
    }
    public struct Space: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let icon: String
    }
    public let format: Format
    public let tabs: [Tab]
    public let spaces: [Space]
    public let folderCount: Int
    public let splitCount: Int
    public let collectedAt: Date?
    public var pinnedCount: Int { tabs.filter { $0.pinned || $0.essential }.count }

    public static func parse(_ data: Data) throws -> SessionPreview {
        let document: Document
        do { document = try JSONDecoder().decode(Document.self, from: MozillaLZ4.decode(data)) }
        catch let error as BackupError { throw error }
        catch { throw BackupError.invalid("The session JSON is invalid or uses an unsupported schema.") }
        let format: Format
        let rawTabs: [RawTab]
        let rawSpaces: [RawSpace]
        if let tabs = document.tabs, let spaces = document.spaces {
            format = .zen; rawTabs = tabs; rawSpaces = spaces
        } else if let windows = document.windows, !windows.isEmpty {
            format = .firefox
            rawTabs = windows.flatMap(\.tabs)
            rawSpaces = windows.flatMap { $0.spaces ?? [] }
        } else {
            throw BackupError.invalid("No supported Zen or Firefox session structure was found.")
        }
        var seen = Set<String>()
        let spaces = rawSpaces.compactMap { raw -> Space? in
            guard let id = raw.uuid ?? raw.id, seen.insert(id).inserted else { return nil }
            return Space(id: id, name: raw.name ?? "Untitled space", icon: raw.icon ?? "")
        }
        let tabs = rawTabs.enumerated().map { index, raw in
            let entries = raw.entries ?? []
            let selected = max(0, min((raw.index ?? entries.count) - 1, entries.count - 1))
            let entry = entries.isEmpty ? nil : entries[selected]
            let url = entry?.url ?? "about:blank"
            return Tab(id: "\(index)", title: entry?.title?.isEmpty == false ? entry?.title ?? url : url,
                url: url, spaceID: raw.zenWorkspace, pinned: raw.pinned ?? false,
                essential: raw.zenEssential ?? false)
        }
        return SessionPreview(format: format, tabs: tabs, spaces: spaces,
            folderCount: document.folders?.count ?? 0, splitCount: document.splitViewData?.count ?? 0,
            collectedAt: document.lastCollected.map { Date(timeIntervalSince1970: $0 / 1000) })
    }

    /// Compare URL multiplicities, so two copies of the same page count as two tabs.
    public func difference(from current: SessionPreview) -> (added: Int, removed: Int) {
        let before = Dictionary(grouping: current.tabs, by: \.url).mapValues(\.count)
        let after = Dictionary(grouping: tabs, by: \.url).mapValues(\.count)
        let keys = Set(before.keys).union(after.keys)
        return (keys.reduce(0) { $0 + max(0, (after[$1] ?? 0) - (before[$1] ?? 0)) },
                keys.reduce(0) { $0 + max(0, (before[$1] ?? 0) - (after[$1] ?? 0)) })
    }

    private struct Document: Decodable {
        let tabs: [RawTab]?
        let spaces: [RawSpace]?
        let windows: [Window]?
        let folders: [IgnoredObject]?
        let splitViewData: [IgnoredObject]?
        let lastCollected: Double?
    }
    private struct Window: Decodable { let tabs: [RawTab]; let spaces: [RawSpace]? }
    private struct RawSpace: Decodable { let uuid: String?; let id: String?; let name: String?; let icon: String? }
    private struct RawTab: Decodable {
        let entries: [Entry]?
        let index: Int?
        let pinned: Bool?
        let zenEssential: Bool?
        let zenWorkspace: String?
    }
    private struct Entry: Decodable { let url: String?; let title: String? }
    private struct IgnoredObject: Decodable {}
}
