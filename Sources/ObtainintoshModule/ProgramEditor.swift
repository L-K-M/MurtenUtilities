import SwiftUI
import ObtainintoshCore

/// The Add/Edit Program dialog. Once the URL names a repository it looks up
/// the latest release, after a typing pause, and offers the programs a
/// multi-program release has.
struct ProgramEditor: View {
    let model: ObtainintoshModel
    let editing: TrackedApp?

    @State private var form: ProgramForm
    @State private var error: String?
    @State private var saving = false
    @State private var lookup: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    init(model: ObtainintoshModel, editing: TrackedApp?, accessToken: String?) {
        self.model = model
        self.editing = editing
        _form = State(initialValue: editing.map { ProgramForm(editing: $0, accessToken: accessToken) } ?? ProgramForm())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(form.isEdit ? "Edit Program" : "Add Program")
                .font(.headline)

            Form {
                TextField("Repository URL", text: $form.url, prompt: Text("https://github.com/owner/repo"))
                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TextField("Program Name", text: $form.name, prompt: Text("Program Name"))
                programInRelease
                Picker("Source", selection: $form.sourceChoice) {
                    ForEach(form.sourceOptions, id: \.self) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .help("A Forgejo instance can be on any domain, so pick Forgejo when its address doesn't say so")
                if form.needsCredentials { credentials }
                TextField("Bundle Identifier", text: $form.bundleID, prompt: Text("Optional, e.g. com.example.app"))
                    .help("When set, the installed copy is found by this identifier instead of the name, even if "
                        + "the app was renamed")
            }
            .formStyle(.columns)
            .disabled(saving)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { close() }
                    .keyboardShortcut(.cancelAction)
                Button(form.isEdit ? "Update" : "Add") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(form.validationError != nil || saving)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
        .onChange(of: form.url) { form.urlDidChange() }
        .onChange(of: form) { scheduleLookup() }
        .onAppear { scheduleLookup() }
        .onDisappear { lookup?.cancel() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var programInRelease: some View {
        TextField("Program in Release", text: $form.assetFilter, prompt: Text("Optional"))
        if let programs = form.releasePrograms, !form.offeredPrograms.isEmpty {
            Picker("Version \(programs.version) has several programs:", selection: chosenProgram) {
                Text("Choose…").tag("")
                ForEach(form.offeredPrograms, id: \.self) { program in
                    Text(program).tag(program)
                }
            }
            if let hint = form.defaultProgramHint {
                Text(hint).font(.callout).foregroundStyle(.secondary)
            }
        } else {
            Text("Only for releases with several programs.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .help("Some repositories publish several programs in each release. Enter the one to track as its "
                    + "file names begin (seance for seance-macos-universal.zip), or a pattern such as *-gtk4-*")
        }
    }

    @ViewBuilder
    private var credentials: some View {
        TextField("Forgejo Username", text: $form.username, prompt: Text("Username (private instances)"))
        SecureField("Application Key", text: $form.accessToken, prompt: Text("Application key (private instances)"))
        Text("Leave both blank for public repositories. The key is kept in your Keychain.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .help("On your Forgejo instance: Settings → Applications → Generate New Token, with read access to the "
                + "repository")
        if RepositoryURL.isPlaintextHTTP(form.url) && !form.accessToken.isEmpty {
            Label("This instance is reached over plain HTTP, so the application key travels unencrypted. Prefer "
                + "https:// beyond a trusted local network.", systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }

    private var chosenProgram: Binding<String> {
        Binding(get: { form.chosenProgram }, set: { form.chooseProgram($0) })
    }

    // MARK: - Actions

    private func scheduleLookup() {
        switch form.lookupChange() {
        case .unchanged:
            return
        case .cancel:
            lookup?.cancel()
            lookup = nil
        case .lookup(let key, let input):
            lookup?.cancel()
            lookup = Task {
                try? await Task.sleep(for: ProgramForm.lookupDelay)
                guard !Task.isCancelled else { return }
                // A convenience: a repository the lookup cannot read is
                // reported by the update check, with its reason.
                guard let programs = try? await model.releasePrograms(for: input), !Task.isCancelled else { return }
                form.receive(programs, forKey: key)
            }
        }
    }

    private func submit() {
        if let problem = form.validationError {
            error = problem
            return
        }
        saving = true
        error = nil
        let input = form.input
        Task {
            defer { saving = false }
            do {
                if let editing {
                    try await model.update(id: editing.id, with: input)
                } else {
                    try await model.add(input)
                }
                close()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func close() {
        lookup?.cancel()
        dismiss()
    }
}
