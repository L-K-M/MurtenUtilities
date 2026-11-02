import Foundation
import ObtainintoshCore

public struct InstalledVersionDetector: InstalledVersionDetecting {
    private let applicationFolders: [URL]
    private let fontFolders: [URL]

    public init(applicationFolders: [URL] = InstalledAppIndex.defaultFolders,
                fontFolders: [URL] = InstalledFontIndex.defaultFolders) {
        self.applicationFolders = applicationFolders
        self.fontFolders = fontFolders
    }

    /// One scan of the application folders for the whole batch.
    public func detectPrograms(_ apps: [TrackedApp]) async -> [InstalledVersion?] {
        guard !apps.isEmpty else { return [] }
        let index = InstalledAppIndex.scan(folders: applicationFolders)
        return apps.map { index.detect(name: $0.name, bundleID: $0.bundleID) }
    }

    /// Scans the font folders only when a lookup names a font.
    public func detectFonts(_ lookups: [FontLookup?]) async -> [FontDetection] {
        let needsIndex = lookups.contains { if case .named? = $0 { return true } else { return false } }
        let index = needsIndex ? InstalledFontIndex.scan(folders: fontFolders) : nil
        return lookups.map { lookup in
            switch lookup {
            case nil:
                return .notAFont
            case .named(let fileName)?:
                return index?.detect(fontFileName: fileName).map(FontDetection.installed) ?? .notInstalled
            case .lastFoundAt(let path)?:
                return InstalledFontIndex.version(at: URL(fileURLWithPath: path))
                    .map { .installed(InstalledVersion(path: path, version: $0)) } ?? .notInstalled
            }
        }
    }
}
