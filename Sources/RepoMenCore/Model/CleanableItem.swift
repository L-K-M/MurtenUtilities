import Foundation

/// One reclaimable directory found by a scan. The `id` is the path, so a rescan
/// naturally replaces earlier findings and the selection survives size updates.
package struct CleanableItem: Identifiable, Hashable, Sendable {
    /// Short human label — "Baegun/target" for project artifacts, or the catalog label
    /// ("Chrome · Profile 14 · Cache") for well-known caches.
    package let label: String
    package let kind: ArtifactKind
    package let path: String

    /// Paths of which at least one must *still exist* at reclaim time — the anchor that
    /// proved this directory regenerable (`…/Cargo.toml`, `…/.venv/pyvenv.cfg`). Empty
    /// for well-known caches, which are re-verified against the static catalog roots
    /// instead. See `Reclaimer`.
    /// Tagged caches additionally re-validate their tag's signature and file type.
    package let anchorPaths: [String]
    package let isKnownCache: Bool

    /// Allocated bytes; 0 until `isMeasured` (the table shows a placeholder meanwhile).
    package var sizeBytes: Int64 = 0
    package var isMeasured: Bool = false
    /// Newest modification time observed while measuring — effectively "last built".
    package var lastModified: Date = .distantPast
    /// A reason for caution ("Chrome is running"), shown as a badge; never blocks.
    package var warning: String?
    /// A root-owned `SystemAreas` item (RTCReporting logs and friends): found by the
    /// admin-gated probe, already measured on arrival, and reclaimed by
    /// `SystemReclaimer` (permanent delete as root) — never by `Reclaimer`, whose
    /// home-only guards it could not pass.
    package var isSystemArea: Bool = false

    package init(label: String, kind: ArtifactKind, path: String, anchorPaths: [String],
                 isKnownCache: Bool, sizeBytes: Int64 = 0, isMeasured: Bool = false,
                 lastModified: Date = .distantPast, warning: String? = nil,
                 isSystemArea: Bool = false) {
        self.label = label
        self.kind = kind
        self.path = path
        self.anchorPaths = anchorPaths
        self.isKnownCache = isKnownCache
        self.sizeBytes = sizeBytes
        self.isMeasured = isMeasured
        self.lastModified = lastModified
        self.warning = warning
        self.isSystemArea = isSystemArea
    }

    /// Keep one row per path; catalog matches retain their reclaim policy and warnings.
    package static func mergingDiscoveries(_ items: [CleanableItem]) -> [CleanableItem] {
        var merged: [CleanableItem] = []
        var indexByID: [String: Int] = [:]

        for item in items {
            guard let index = indexByID[item.id] else {
                indexByID[item.id] = merged.count
                merged.append(item)
                continue
            }
            if item.isKnownCache && !merged[index].isKnownCache {
                merged[index] = item
            }
        }
        return merged
    }

    package var id: String { path }
    package var url: URL { URL(fileURLWithPath: path) }
    package var category: ArtifactCategory { kind.category }
}
