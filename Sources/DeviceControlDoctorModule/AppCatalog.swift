import AppKit
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

    @MainActor static func installedApps(recordedClients: Set<String>) -> [WatchedApp] {
        var result: [WatchedApp] = []
        var seen = Set<String>()
        func append(_ app: WatchedApp?) {
            guard let app, app.bundleID != Bundle.main.bundleIdentifier else { return }
            let key = app.bundleID + "|" + app.path
            if seen.insert(key).inserted { result.append(app) }
        }
        let roots = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                append(app(at: url))
            }
        }
        for running in NSWorkspace.shared.runningApplications {
            if let url = running.bundleURL { append(app(at: url)) }
        }
        for client in recordedClients {
            if ClientIdentifier.isBundleIdentifier(client) {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: client) { append(app(at: url)) }
            } else if client.hasPrefix("/"), let range = client.range(of: ".app/", options: .backwards) {
                let path = String(client[..<range.lowerBound]) + ".app"
                append(app(at: URL(fileURLWithPath: path), clientIdentifier: client))
            }
        }
        // The engine is a separate permission client embedded in the editor bundle.
        for editor in result where editor.bundleID == "com.stairways.keyboardmaestro.editor" {
            append(app(at: URL(fileURLWithPath: editor.path).appendingPathComponent("Contents/MacOS/Keyboard Maestro Engine.app")))
        }
        return result.sorted {
            let a = recordedClients.contains($0.bundleID), b = recordedClients.contains($1.bundleID)
            return a == b ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : a
        }
    }
}
