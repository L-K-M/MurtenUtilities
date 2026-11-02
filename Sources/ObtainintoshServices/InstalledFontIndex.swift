import Foundation
import ObtainintoshCore

/// One pass over the font folders, reusable for every tracked font. Font
/// Book keeps a font's file name when it installs it, so an installed font
/// is found by the name of the file the entry downloads, in any installable
/// format: an entry downloading `C64Keyboard-Regular.ttf` is installed when
/// `C64Keyboard-Regular.otf` is.
public struct InstalledFontIndex: Sendable {
    /// How deep font folders are searched.
    static let maximumDepth = 4

    /// Lowercased file name without its extension → font files, in scan order.
    let fontsByName: [String: [URL]]

    /// The user's font folder first, then the system-wide one.
    public static var defaultFolders: [URL] {
        [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Fonts", isDirectory: true),
         URL(fileURLWithPath: "/Library/Fonts", isDirectory: true)]
    }

    public static func scan(folders: [URL] = defaultFolders) -> InstalledFontIndex {
        var fontsByName: [String: [URL]] = [:]
        for folder in folders {
            collect(folder, depth: 0, into: &fontsByName)
        }
        return InstalledFontIndex(fontsByName: fontsByName)
    }

    /// Where the font a file name stands for is installed, and its version.
    /// Of several copies the newest wins: an update installed beside the old
    /// copy is the one the user just fetched.
    public func detect(fontFileName: String) -> InstalledVersion? {
        guard let key = Self.key(fontFileName), let copies = fontsByName[key] else { return nil }
        var newest: InstalledVersion?
        for copy in copies {
            guard let version = Self.version(at: copy) else { continue }
            if let current = newest, !Self.isNewer(version, than: current.version) { continue }
            newest = InstalledVersion(path: copy.path, version: version)
        }
        return newest
    }

    /// The version of the font file at `url`, or nil when it is gone or
    /// cannot be read.
    public static func version(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var reader = FontVersionReader()
        var step = reader.start()
        while true {
            switch step {
            case .version(let version):
                return version
            case .read(let range):
                do {
                    try handle.seek(toOffset: range.lowerBound)
                    let bytes = try handle.read(upToCount: Int(range.upperBound - range.lowerBound)) ?? Data()
                    step = try reader.advance([UInt8](bytes))
                } catch {
                    return nil
                }
            }
        }
    }

    // MARK: - Scanning

    /// Indexes the font files under `folder`. Symbolic links to folders are
    /// not followed, so a link loop cannot trap the scan.
    private static func collect(_ folder: URL, depth: Int, into fontsByName: inout [String: [URL]]) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)
        else { return }

        // Listing order is arbitrary; sorting keeps which copy wins a tie stable.
        for entry in entries.sorted(by: { $0.path < $1.path }) {
            let values = try? entry.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true && values?.isSymbolicLink != true {
                if depth < maximumDepth { collect(entry, depth: depth + 1, into: &fontsByName) }
                continue
            }
            guard let key = key(entry.lastPathComponent) else { continue }
            fontsByName[key, default: []].append(entry)
        }
    }

    /// `C64Keyboard-Regular.TTF` → `c64keyboard-regular`; nil for a file
    /// that is no installable font.
    static func key(_ fileName: String) -> String? {
        guard FontFile.isFontFile(fileName), let dot = fileName.lastIndex(of: ".") else { return nil }
        return String(fileName[..<dot]).lowercased()
    }

    /// Numeric component-wise order, so 1.10 is newer than 1.9.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ version: String) -> [UInt64] {
            version.split(separator: ".", omittingEmptySubsequences: false).map { UInt64($0) ?? 0 }
        }
        return parts(current).lexicographicallyPrecedes(parts(candidate))
    }
}
