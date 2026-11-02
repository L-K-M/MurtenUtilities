import Foundation
import ObtainintoshCore

/// One pass over the application folders, reusable for every tracked
/// program. Reads only: folder listings and `Info.plist` files, neither of
/// which macOS guards with a privacy prompt.
///
/// A program is found by the bundle identifier its entry records, when it
/// records one, and otherwise by name, as the standalone app does: the
/// typed name matched against `<name>.app`, exactly first and then
/// case-insensitively, folder by folder.
public struct InstalledAppIndex: Sendable {
    struct Folder: Sendable {
        let url: URL
        /// Bundles in listing order.
        let bundles: [URL]
        /// Lowercased name without `.app` → bundles carrying it.
        let bundlesByName: [String: [URL]]
    }

    let folders: [Folder]

    /// `/Applications`, then `~/Applications`.
    public static var defaultFolders: [URL] {
        [URL(fileURLWithPath: "/Applications", isDirectory: true),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)]
    }

    public static func scan(folders: [URL] = defaultFolders) -> InstalledAppIndex {
        let fileManager = FileManager.default
        return InstalledAppIndex(folders: folders.map { folder in
            let entries = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            return index(folder, entries: entries.sorted { $0.lastPathComponent < $1.lastPathComponent })
        })
    }

    static func index(_ folder: URL, entries: [URL]) -> Folder {
        var bundles: [URL] = []
        var byName: [String: [URL]] = [:]
        for entry in entries where entry.pathExtension == "app" {
            bundles.append(entry)
            byName[entry.deletingPathExtension().lastPathComponent.lowercased(), default: []].append(entry)
        }
        return Folder(url: folder, bundles: bundles, bundlesByName: byName)
    }

    /// Where the program is installed and its version, or nil.
    public func detect(name: String, bundleID: String?) -> InstalledVersion? {
        if let bundleID, !bundleID.isEmpty {
            for bundle in folders.flatMap(\.bundles) where Self.bundleIdentifier(of: bundle) == bundleID {
                if let version = Self.version(of: bundle) { return InstalledVersion(path: bundle.path, version: version) }
            }
        }
        for candidate in candidates(for: name) {
            if let version = Self.version(of: candidate) { return InstalledVersion(path: candidate.path, version: version) }
        }
        return nil
    }

    /// The exact-cased `<name>.app` first, then case-insensitive matches,
    /// folder by folder, so which bundle wins does not depend on the index.
    func candidates(for name: String) -> [URL] {
        var paths: [URL] = []
        for folder in folders {
            // A name with a slash would leave the folder; it can only match
            // case-insensitively against the listing.
            if !name.isEmpty, !name.contains("/") {
                paths.append(folder.url.appendingPathComponent("\(name).app", isDirectory: true))
            }
            paths += folder.bundlesByName[name.lowercased()] ?? []
        }
        return paths
    }

    // MARK: - Bundles

    /// `CFBundleShortVersionString`, else `CFBundleVersion`.
    static func version(of bundle: URL) -> String? {
        guard let info = infoDictionary(of: bundle) else { return nil }
        for key in ["CFBundleShortVersionString", "CFBundleVersion"] {
            if let value = text(info[key]), !value.isEmpty { return value }
        }
        return nil
    }

    static func bundleIdentifier(of bundle: URL) -> String? {
        infoDictionary(of: bundle).flatMap { text($0["CFBundleIdentifier"]) }
    }

    private static func infoDictionary(of bundle: URL) -> [String: Any]? {
        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    private static func text(_ value: Any?) -> String? {
        if let string = value as? String { return string.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}
