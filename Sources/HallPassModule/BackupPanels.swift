import AppKit
import UniformTypeIdentifiers

@MainActor
enum BackupPanels {
    static func open(in window: NSWindow, completion: @escaping @MainActor (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Local Network Access Backup"
        panel.prompt = "Import"
        panel.message = "The backup replaces the draft. You can undo the import."
        panel.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated { completion(response == .OK ? panel.url : nil) }
        }
    }

    static func save(in window: NSWindow, completion: @escaping @MainActor (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "HallPass-Backup.json"
        panel.title = "Export Saved State"
        panel.prompt = "Export"
        panel.message = "Contains the most recently loaded or saved state. Changes you have not applied are not included."
        panel.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated { completion(response == .OK ? panel.url : nil) }
        }
    }
}
