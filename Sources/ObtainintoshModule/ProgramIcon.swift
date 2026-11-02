import SwiftUI
import ObtainintoshCore

/// The repository owner's GitHub avatar, or a document symbol for other
/// sources and when the avatar cannot load, in one fixed box so rows line up.
struct ProgramIcon: View {
    let app: TrackedApp
    private static let size: CGFloat = 18

    var body: some View {
        Group {
            if let url = avatarURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        placeholder
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                placeholder
            }
        }
        .frame(width: Self.size, height: Self.size)
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: "doc")
            .foregroundStyle(.secondary)
    }

    /// `https://avatars.githubusercontent.com/<owner>?size=40` for GitHub.
    private var avatarURL: URL? {
        guard app.sourceType == .github, let owner = try? RepositoryURL.parseGitHub(app.sourceURL).owner,
              let encoded = owner.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://avatars.githubusercontent.com/\(encoded)?size=40")
    }
}
