import SwiftUI

/// The check and download progress the standalone app showed in modal
/// dialogs, as a panel over the pane. A download can be cancelled.
struct ProgressPanel: View {
    let model: ObtainintoshModel

    var body: some View {
        if let download = model.downloadProgress {
            panel {
                line("Downloading:", download.fileName)
                ProgressView(value: Double(download.downloaded), total: Double(max(download.total, 1)))
                    .accessibilityLabel("Download progress for \(download.fileName)")
                HStack {
                    Button("Cancel") { model.cancelDownload() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Text("\(Self.bytes(download.downloaded)) of \(Self.bytes(download.total))")
                        .monospacedDigit()
                }
            }
        } else if model.isChecking {
            panel {
                line("Checking for updates:", model.checkProgress?.appName ?? "…")
                if let progress = model.checkProgress {
                    // Each step is announced before its program is checked,
                    // so `position - 1` are done.
                    ProgressView(value: Double(progress.position - 1), total: Double(max(progress.total, 1)))
                        .accessibilityLabel("Update check progress")
                    HStack {
                        Spacer()
                        Text("\(progress.position) of \(progress.total)").monospacedDigit()
                    }
                } else {
                    ProgressView().progressViewStyle(.linear).accessibilityLabel("Update check progress")
                }
            }
        }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(16)
        .frame(width: 400)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.separator) }
        .shadow(radius: 8)
        .accessibilityElement(children: .contain)
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
            Text(value).bold().lineLimit(1).truncationMode(.middle)
        }
    }

    /// `512 B`, `40 KB`, `3.2 MB`, as the standalone app wrote sizes.
    static func bytes(_ count: UInt64) -> String {
        if count < 1024 { return "\(count) B" }
        if count < 1024 * 1024 { return "\(Int((Double(count) / 1024).rounded())) KB" }
        return String(format: "%.1f MB", Double(count) / (1024 * 1024))
    }
}
