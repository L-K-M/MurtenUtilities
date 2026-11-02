import SwiftUI
import ObtainintoshCore

/// The GitHub token, in the pane's Settings sheet and the suite's Settings
/// window. Public repositories work without one; it raises GitHub's limit
/// from 60 to 5,000 requests an hour. It is kept in the Keychain.
struct ObtainintoshSettingsView: View {
    enum Presentation {
        /// A sheet over the pane: Cancel, and closes after saving.
        case sheet
        /// A tab of the suite's Settings window.
        case settingsWindow
    }

    let model: ObtainintoshModel
    let presentation: Presentation

    @State private var token = ""
    @State private var loaded = false
    @State private var saving = false
    @State private var saved = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if presentation == .sheet {
                Text("Settings").font(.headline)
            }
            Form {
                SecureField("GitHub Personal Access Token", text: $token, prompt: Text("ghp_xxxxxxxxxxxx (optional)"))
                    .disabled(!loaded || saving)
                HStack(spacing: 6) {
                    Text("Optional. Increases API rate limits.")
                        .help("Generate a fine-grained token with read-only access to public repositories")
                    Link("Generate token →", destination: URL(string: "https://github.com/settings/tokens")!)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .formStyle(.columns)

            if let error {
                Text(error).italic().fixedSize(horizontal: false, vertical: true)
            }
            if saved {
                Text("✓ Settings saved successfully!").bold()
            }

            HStack {
                Spacer()
                if presentation == .sheet {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(saving)
                }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!loaded || saving || (saved && presentation == .sheet))
            }
        }
        .padding(20)
        .frame(minWidth: 420)
        // Reading the stored token may show the Keychain's prompt, so it
        // happens only once this view is on screen.
        .task {
            token = await model.gitHubToken() ?? ""
            loaded = true
        }
        .onChange(of: token) { saved = false }
    }

    private func save() {
        saving = true
        error = nil
        Task {
            defer { saving = false }
            do {
                try await model.saveGitHubToken(token)
                saved = true
                if presentation == .sheet {
                    try? await Task.sleep(for: .seconds(1))
                    dismiss()
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
