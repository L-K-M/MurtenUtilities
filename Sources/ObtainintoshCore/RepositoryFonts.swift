import Foundation

/// Fonts committed to a repository that publishes no releases, such as
/// github.com/szabadkai/c64-keyboard-font:
///
/// ```
///   fonts/C64Keyboard-Regular.ttf  ─┐ font "c64keyboard-regular",
///   fonts/C64Keyboard-Regular.otf  ─┘ version 1.107 (declared by the font)
///   C64-Keyboard.zip                  not a font file, ignored
/// ```
///
/// The files take the place of a release's assets, so program filters and
/// the platform picker work on them unchanged. With no release tag to go by,
/// the version is the one the chosen font declares (read by the services).
public struct RepositoryFonts: Equatable, Sendable {
    /// Shallowest path first, so of two copies of a font the picker keeps
    /// `fonts/A.ttf` over `docs/site/fonts/A.ttf`.
    public let files: [ReleaseAsset]

    /// The font files among a listing's entries, or nil when there are none.
    /// `rawURL` gives the URL that serves a path's contents.
    public static func fromTree(_ entries: [RepositoryTree.Entry],
                                rawURL: (String) throws -> String) rethrows -> RepositoryFonts? {
        let fonts = entries
            .filter { $0.kind == RepositoryTree.Entry.fileKind && FontFile.isFontFile($0.path) }
            .sorted { lhs, rhs in
                let depth = { (entry: RepositoryTree.Entry) in entry.path.filter { $0 == "/" }.count }
                if depth(lhs) != depth(rhs) { return depth(lhs) < depth(rhs) }
                return lhs.path.utf8.lexicographicallyPrecedes(rhs.path.utf8)
            }

        let files = try fonts.map { entry in
            let name = entry.path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init)
                ?? entry.path
            return ReleaseAsset(name: name, browserDownloadURL: try rawURL(entry.path), size: entry.size)
        }
        return files.isEmpty ? nil : RepositoryFonts(files: files)
    }

    /// The font to download.
    public func pick(filter: AssetFilter?, architecture: CPUArchitecture = .current) throws -> ReleaseAsset {
        if let font = AssetPicker.compatibleAsset(files, filter: filter, architecture: architecture) { return font }

        if let filter {
            throw ObtainintoshError("The repository publishes no releases, and none of its font files is "
                + "\"\(filter.canonical)\". Its fonts: \(ReleaseSelection.listPrograms(names(architecture: architecture)))")
        }
        throw ObtainintoshError("The repository publishes no releases, and its font files are all marked for "
            + "other systems")
    }

    /// The program names of the fonts this Mac can use, sorted.
    public func names(architecture: CPUArchitecture = .current) -> [String] {
        ReleaseSelection.sortedProgramNames(files).filter { name in
            AssetPicker.compatibleAsset(files, filter: .program(name), architecture: architecture) != nil
        }
    }
}
