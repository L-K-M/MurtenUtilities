import Foundation

/// Reads the version a font file declares. Fonts carry no bundle metadata:
/// the version lives in the `name` table, which the table directory at the
/// start of the file points at.
///
/// ```
///   ┌───────────────────┐
///   │ table directory   │── "name" at offset 9184, 412 bytes ──┐
///   ├───────────────────┤                                      │
///   │ glyf, cmap, …     │                                      │
///   │ name              │◀─────────────────────────────────────┘
///   └───────────────────┘   nameID 5: "Version 1.107; ttfautohint"
/// ```
///
/// The reader does no I/O. It names the byte range it needs next and is fed
/// those bytes, so a font in a repository is read with a few small range
/// requests instead of a download, and an installed one with a few seeks.
/// A collection (`.ttc`) adds one step: its header points at the first
/// font's table directory. A version string without a number adds another:
/// the revision in the `head` table stands in.
public enum FontFile {
    /// Installable desktop font formats, most preferred first. Web fonts
    /// (`.woff`, `.woff2`) are left out: desktop systems do not install them.
    public static let extensions = [".ttf", ".otf", ".ttc", ".otc"]

    public static func isFontFile(_ fileName: String) -> Bool {
        let name = fileName.asciiLowercased()
        return extensions.contains { name.hasSuffix($0) }
    }
}
