import AppKit
import DoctorCore

extension AppCatalog {
    /// Never offered for watching: the suite itself, and the standalone app
    /// this module replaces. A fixed list rather than `Bundle.main`, which
    /// is the suite's identity now.
    static let excludedBundleIdentifiers: Set<String> = ["ch.lkmc.MurtenUtilities", "ch.lkmc.DeviceControlDoctor"]

    @MainActor static func installedApps(recordedClients: Set<String>) -> [WatchedApp] {
        var result: [WatchedApp] = []
        var seen = Set<String>()
        func append(_ app: WatchedApp?) {
            guard let app, !excludedBundleIdentifiers.contains(app.bundleID) else { return }
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
