import SwiftUI

/// The pane's messages, bottom right, newest last. Success and information
/// fade after a while; errors stay until dismissed. Never modal.
struct NoticeStack: View {
    let model: ObtainintoshModel
    private static let lifetime: Duration = .seconds(8)

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(model.notices.suffix(4)) { notice in
                card(notice)
                    .task(id: notice.id) {
                        guard notice.kind != .error else { return }
                        try? await Task.sleep(for: Self.lifetime)
                        model.dismiss(notice)
                    }
            }
        }
        .padding(16)
        .frame(maxWidth: 420, alignment: .trailing)
    }

    private func card(_ notice: ObtainintoshModel.Notice) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol(notice.kind))
                .foregroundStyle(color(notice.kind))
                .accessibilityHidden(true)
            Text(notice.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                model.dismiss(notice)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.separator) }
        .accessibilityElement(children: .combine)
    }

    private func symbol(_ kind: ObtainintoshModel.Notice.Kind) -> String {
        switch kind {
        case .success: return "checkmark.circle"
        case .info: return "info.circle"
        case .error: return "exclamationmark.triangle"
        }
    }

    private func color(_ kind: ObtainintoshModel.Notice.Kind) -> Color {
        switch kind {
        case .success: return .green
        case .info: return .secondary
        case .error: return .orange
        }
    }
}
