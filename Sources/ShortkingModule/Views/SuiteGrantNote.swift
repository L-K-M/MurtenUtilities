import SwiftUI

/// Says whose permission a grant is, wherever the pane asks for one.
///
/// Accessibility and Input Monitoring belong to the app that asks, and that is
/// Murten Utilities now, not the standalone Shortking. This build is ad-hoc
/// signed, and macOS ties a grant to the exact build it was given to, so every
/// update loses it (PLAN.md, Signing).
struct SuiteGrantNote: View {
    var body: some View {
        Label {
            Text("Murten Utilities holds this permission for Shortking, separately from the "
                + "standalone Shortking app. Because this build is ad-hoc signed, macOS forgets "
                + "the grant after every update of Murten Utilities: turn it off and on again in "
                + "System Settings after updating.")
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
