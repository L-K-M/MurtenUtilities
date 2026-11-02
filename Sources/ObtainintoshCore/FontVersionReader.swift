import Foundation

/// Steps through a font file to its declared version:
///
///     var reader = FontVersionReader()
///     var step = reader.start()
///     while case .read(let range) = step { step = try reader.advance(read(range)) }
public struct FontVersionReader: Sendable {
    /// What the reader needs next.
    public enum Step: Equatable, Sendable {
        /// Feed these bytes of the file to `FontVersionReader.advance`. A read
        /// that reaches past the end of the file returns what there is.
        case read(Range<UInt64>)
        /// The version, without its "Version" prefix: `1.107`.
        case version(String)
    }

    /// The first read: enough for a collection header, or for a table
    /// directory of up to 255 tables (12 + 16 × 255 bytes).
    public static let headerLength: UInt64 = 4096
    /// More than any real `name` or `head` table needs, so a corrupt
    /// directory cannot make the reader fetch gigabytes.
    static let maximumTableLength: UInt64 = 1024 * 1024

    static let nameTableTag = Array("name".utf8)
    static let headTableTag = Array("head".utf8)
    static let collectionTag = Array("ttcf".utf8)
    /// TrueType (`0x00010000`, Apple's `true`) and CFF-based OpenType (`OTTO`).
    static let sfntVersions: [[UInt8]] = [[0, 1, 0, 0], Array("OTTO".utf8), Array("true".utf8)]

    static let versionNameID: UInt16 = 5
    static let unicodePlatform: UInt16 = 0
    static let macintoshPlatform: UInt16 = 1
    static let windowsPlatform: UInt16 = 3
    /// Platforms whose `name` strings are UTF-16BE, most preferred first.
    static let utf16Platforms: [UInt16] = [windowsPlatform, unicodePlatform]

    /// Where the `head` table keeps `fontRevision`, a 16.16 fixed-point number.
    static let fontRevisionOffset = 4
    static let noVersion = "The font declares no version"
    static let notAFont = "Not a font file"

    private enum State: Sendable {
        case header
        case directory
        /// Reading the `name` table, with the `head` table as the fallback.
        case nameTable(head: Range<UInt64>?)
        case headTable
    }

    private var state: State = .header

    public init() {}

    public func start() -> Step {
        .read(0..<Self.headerLength)
    }

    public mutating func advance(_ bytes: [UInt8]) throws -> Step {
        let current = state
        state = .header
        switch current {
        case .header where bytes.starts(with: Self.collectionTag):
            // A collection's header lists the offset of each font's table
            // directory; the first font speaks for the file.
            guard let offset = Self.readUInt32(bytes, at: 12) else {
                throw ObtainintoshError("Truncated font collection")
            }
            state = .directory
            let start = UInt64(offset)
            return .read(start..<start + Self.headerLength)
        case .header, .directory:
            let tables = try Self.versionTables(bytes)
            guard let name = tables.name else { return try readHead(tables.head) }
            state = .nameTable(head: tables.head)
            return .read(name)
        case .nameTable(let head):
            if let version = Self.declaredVersion(bytes) { return .version(version) }
            return try readHead(head)
        case .headTable:
            guard let revision = Self.fontRevision(bytes) else { throw ObtainintoshError(Self.noVersion) }
            return .version(revision)
        }
    }

    private mutating func readHead(_ head: Range<UInt64>?) throws -> Step {
        guard let head else { throw ObtainintoshError(Self.noVersion) }
        state = .headTable
        return .read(head)
    }

    // MARK: - Tables

    /// Finds the version tables in a table directory. Offsets count from the
    /// start of the file, in a collection too.
    private static func versionTables(_ directory: [UInt8]) throws -> (name: Range<UInt64>?, head: Range<UInt64>?) {
        guard directory.count >= 4 else { throw ObtainintoshError(notAFont) }
        let sfntVersion = Array(directory[0..<4])
        guard sfntVersions.contains(sfntVersion) else { throw ObtainintoshError(notAFont) }
        guard let tableCount = readUInt16(directory, at: 4) else { throw ObtainintoshError("Truncated font header") }

        var name: Range<UInt64>?
        var head: Range<UInt64>?
        for index in 0..<Int(tableCount) {
            let record = 12 + 16 * index
            // A directory reaching past the first read ends there; the tables
            // found before that still count.
            guard record + 4 <= directory.count,
                  let offset = readUInt32(directory, at: record + 8),
                  let length = readUInt32(directory, at: record + 12) else { break }
            let tag = Array(directory[record..<record + 4])
            let isName = tag == nameTableTag
            guard isName || tag == headTableTag else { continue }

            let start = UInt64(offset)
            let size = UInt64(length)
            if size > maximumTableLength { throw ObtainintoshError("The font's tables are implausibly large") }
            // An empty table holds no version.
            guard size > 0 else { continue }
            if isName { name = start..<start + size } else { head = start..<start + size }
        }
        return (name, head)
    }

    /// The version string of a `name` table, preferring the Unicode encodings
    /// over the legacy Macintosh one. nil when no version string has a number.
    private static func declaredVersion(_ table: [UInt8]) -> String? {
        guard let recordCount = readUInt16(table, at: 2), let stringsOffset = readUInt16(table, at: 4) else {
            return nil
        }

        var utf16: [(rank: Int, text: String)] = []
        var macintosh: [String] = []
        for index in 0..<Int(recordCount) {
            let record = 6 + 12 * index
            guard let platform = readUInt16(table, at: record),
                  let nameID = readUInt16(table, at: record + 6),
                  let length = readUInt16(table, at: record + 8),
                  let offset = readUInt16(table, at: record + 10) else { break }
            guard nameID == versionNameID else { continue }

            let start = Int(stringsOffset) + Int(offset)
            let end = start + Int(length)
            guard end <= table.count else { continue }
            let bytes = Array(table[start..<end])
            if let rank = utf16Platforms.firstIndex(of: platform) {
                utf16.append((rank, decodeUTF16BigEndian(bytes)))
            } else if platform == macintoshPlatform {
                macintosh.append(String(decoding: bytes, as: UTF8.self))
            }
        }

        // A stable sort, so records of one platform keep their table order.
        let ranked = utf16.enumerated()
            .sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }
            .map(\.element.text)
        for text in ranked + macintosh {
            if let version = versionNumber(text) { return version }
        }
        return nil
    }

    /// The `head` table's revision. Font tools derive it from the version,
    /// which it stores inexactly: 1.107 as 1.10699…, so three decimals
    /// restore it.
    private static func fontRevision(_ head: [UInt8]) -> String? {
        guard let raw = readUInt32(head, at: fontRevisionOffset) else { return nil }
        let revision = Int32(bitPattern: raw)
        guard revision > 0 else { return nil }
        return String(format: "%.3f", Double(revision) / 65536.0)
    }

    /// The number of a `name` table version string, which by convention reads
    /// "Version 1.107" and may continue with build notes:
    /// `Version 2.304; ttfautohint (v1.8.4)` → `2.304`.
    static func versionNumber(_ text: String) -> String? {
        var rest = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if rest.prefix(7).lowercased() == "version" { rest = rest.dropFirst(7) }
        rest = rest.drop { $0 == ":" || $0.isWhitespace }
        if rest.first == "v" || rest.first == "V" { rest = rest.dropFirst() }

        var number = String(rest.prefix { ($0.isASCII && $0.isNumber) || $0 == "." })
        while number.hasSuffix(".") { number.removeLast() }
        guard let first = number.first, first.isASCII, first.isNumber else { return nil }
        return number
    }

    private static func decodeUTF16BigEndian(_ bytes: [UInt8]) -> String {
        var units: [UInt16] = []
        units.reserveCapacity(bytes.count / 2)
        var index = 0
        while index + 1 < bytes.count {
            units.append(UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1]))
            index += 2
        }
        return String(decoding: units, as: UTF16.self)
    }

    static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= bytes.count else { return nil }
        return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(bytes[offset + $1]) }
    }
}
