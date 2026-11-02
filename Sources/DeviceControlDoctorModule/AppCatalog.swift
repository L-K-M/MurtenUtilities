import Foundation
import DoctorCore

enum AppCatalog {
    static func app(at url: URL, clientIdentifier: String? = nil) -> WatchedApp? {
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        guard url.pathExtension.lowercased() == "app",
              let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let identifier = clientIdentifier ?? (info["CFBundleIdentifier"] as? String), !identifier.isEmpty else { return nil }
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let version = info["CFBundleShortVersionString"] as? String ?? "Unknown"
        return WatchedApp(name: name, bundleID: identifier, path: url.path, version: version)
    }
}
