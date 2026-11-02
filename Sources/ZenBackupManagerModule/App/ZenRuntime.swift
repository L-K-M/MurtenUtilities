import AppKit

enum ZenRuntime {
    static var applications: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            let id = ($0.bundleIdentifier ?? "").lowercased()
            return id == "app.zen-browser.zen" || id.hasPrefix("app.zen-browser.") ||
                $0.bundleURL?.lastPathComponent == "Zen Browser.app"
        }
    }
    static var isRunning: Bool { !applications.isEmpty }

    @MainActor static func quit() {
        for app in applications { app.terminate() }
    }
    @MainActor static func open() async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "app.zen-browser.zen") else {
            throw BackupError.invalid("Zen could not be found. Open your installed copy from Finder.")
        }
        try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}
