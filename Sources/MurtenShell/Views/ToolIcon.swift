import SwiftUI
import MurtenCore

/// The suite's illustrated tool identity; labels supply its accessible name.
/// Callers supply a frame; artwork fits uniformly within that rectangle.
struct ToolIcon: View {
    let module: SuiteModule

    var body: some View {
        Group {
            if let artwork = ToolArtwork(rawValue: module.id) {
                Canvas { context, size in
                    artwork.draw(in: context, fitting: size)
                }
            } else {
                Image(systemName: module.systemImage)
                    .resizable()
                    .scaledToFit()
            }
        }
        .accessibilityHidden(true)
    }
}
