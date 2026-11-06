import SwiftUI
import MurtenCore

/// The suite's illustrated tool identity; labels supply its accessible name.
struct ToolIcon: View {
    let module: SuiteModule

    var body: some View {
        Group {
            if let artwork = ToolArtwork(rawValue: module.id) {
                Canvas { context, size in
                    context.scaleBy(x: size.width / 128, y: size.height / 128)
                    artwork.draw(in: context)
                }
                .aspectRatio(1, contentMode: .fit)
            } else {
                Image(systemName: module.systemImage)
                    .resizable()
                    .scaledToFit()
            }
        }
        .accessibilityHidden(true)
    }
}
