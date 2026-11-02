import Foundation

/// A copy of ObtainintoshCoreTests/TestFonts.swift (test targets cannot
/// share sources). Builds minimal font files: a table directory with a `head` table and a
/// `name` table holding the given version strings as (platform, text)
/// records. The port of the Rust tests' `font_bytes`/`sfnt_at`.
enum TestFonts {
    static let unicodePlatform: UInt16 = 0
    static let macintoshPlatform: UInt16 = 1
    static let windowsPlatform: UInt16 = 3
    static let fontRevisionOffset = 4
    /// Where the `name` table's length sits in an `sfnt` font: the second
    /// directory record, twelve bytes in.
    static let nameLengthOffset = 12 + 16 + 12

    static func font(_ versions: [(UInt16, String)]) -> [UInt8] {
        sfnt(at: 0, version: [0, 1, 0, 0], versions: versions, revision: 0)
    }

    static func font(declaring version: String) -> [UInt8] {
        font([(windowsPlatform, "Version \(version)")])
    }

    static func sfnt(at base: Int, version sfntVersion: [UInt8], versions: [(UInt16, String)],
                     revision: Int32) -> [UInt8] {
        var strings: [UInt8] = []
        var records: [UInt8] = []
        for (platform, text) in versions {
            let encoded: [UInt8] = platform == macintoshPlatform
                ? Array(text.utf8)
                : text.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
            for value in [platform, 1, 0x409, 5] { records += be16(value) }
            records += be16(UInt16(encoded.count))
            records += be16(UInt16(strings.count))
            strings += encoded
        }
        var name: [UInt8] = []
        name += be16(0)
        name += be16(UInt16(versions.count))
        name += be16(UInt16(6 + records.count))
        name += records
        name += strings

        var head = [UInt8](repeating: 0, count: 54)
        let revisionBytes = be32(UInt32(bitPattern: revision))
        head.replaceSubrange(fontRevisionOffset..<fontRevisionOffset + 4, with: revisionBytes)
        let tablesStart = base + 12 + 16 * 2
        let nameOffset = tablesStart + head.count

        var font = sfntVersion
        font += be16(2)
        font += [UInt8](repeating: 0, count: 6)
        for (tag, offset, length) in [("head", tablesStart, head.count), ("name", nameOffset, name.count)] {
            font += Array(tag.utf8)
            font += [0, 0, 0, 0]
            font += be32(UInt32(offset))
            font += be32(UInt32(length))
        }
        font += head
        font += name
        return font
    }

    static func be16(_ value: UInt16) -> [UInt8] { [UInt8(value >> 8), UInt8(value & 0xFF)] }

    static func be32(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }
}
