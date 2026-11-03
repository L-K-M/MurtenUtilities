import AppKit
import UniformTypeIdentifiers
import CoreographyServices

/// Open Recording… (Command-O): reads a `.coreotrace` the person picked into
/// the model. The standalone app also opened recordings from Finder and
/// `coreography://` links; the suite registers neither, so the panel is the
/// way in.
@MainActor
enum RecordingOpener {
    static func choose(into model: DashboardModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.coreographyRecording]
        panel.allowsMultipleSelection = false
        // The app is not sandboxed, so a picked file is readable as is.
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url, into: model)
    }

    static func open(_ url: URL, into model: DashboardModel) {
        Task {
            let data = await Task.detached { () -> Data? in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard size <= Recording.maximumBytes else { return nil }
                return try? Data(contentsOf: url)
            }.value
            guard let data else {
                model.reportRecordingFailure("The recording could not be read")
                return
            }
            await model.openRecording(data, fileName: url.deletingPathExtension().lastPathComponent)
        }
    }
}

extension UTType {
    /// The standalone app exports `ch.lkmc.coreography.trace`; the suite's
    /// Info.plist does not, so the type is found by its extension: the
    /// declared type while Coreography is installed, otherwise a dynamic
    /// type that still filters and names `.coreotrace` files.
    static let coreographyRecording = UTType(filenameExtension: Recording.fileExtension, conformingTo: .json) ?? .json
}
