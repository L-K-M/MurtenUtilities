import AppKit
import SwiftUI

/// The standalone app's Settings window without its update checker: the
/// suite checks for its own updates.
struct ZenBackupSettings: View {
    let safetyRoot: URL

    var body: some View {
        Form {
            Text("Backups and tab previews stay on this Mac. Safety copies are kept until you delete them in Finder.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Show Safety Copies in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: safetyRoot.path)
            }
        }.padding(24)
    }
}
