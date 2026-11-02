import SwiftUI

/// Offers, once, to bring the standalone app's tracked programs over. Never
/// automatic, and the standalone app's own list is left as it is.
struct StandaloneImportBanner: View {
    let count: Int
    let onImport: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Import from the Obtainintosh app?").bold()
                Text("It tracks \(count == 1 ? "1 program" : "\(count) programs"). Importing copies them here and "
                    + "moves their tokens into your Keychain; the app's own list is not changed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Don't Import", action: onDecline)
            Button("Import", action: onImport)
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .accessibilityElement(children: .contain)
    }
}
