import AppKit

struct FinderRevealer: FileRevealing {
    @MainActor func reveal(_ url: URL) -> Bool {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
    }
}
