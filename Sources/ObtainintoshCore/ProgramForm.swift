import Foundation

/// The Add/Edit Program dialog's state and rules, apart from the view: the
/// name that follows the URL until the user types one, the program lookup
/// that offers a multi-program release's programs, and what gets submitted.
public struct ProgramForm: Equatable, Sendable {
    public enum SourceChoice: Hashable, Sendable {
        /// Leaves the forge to be detected from the URL.
        case automatic
        case source(SourceType)

        public var label: String {
            switch self {
            case .automatic: return "Detect automatically"
            case .source(let type): return type.displayName
            }
        }
    }

    /// What a field change means for the program lookup.
    public enum LookupChange: Equatable, Sendable {
        /// The inputs are as before; keep whatever is pending.
        case unchanged
        /// The inputs changed and name no repository: cancel any pending lookup.
        case cancel
        /// Look up the programs for these inputs after the typing pause.
        case lookup(key: String, input: SourceInput)
    }

    /// Long enough that typing a URL by hand does not spend a forge API
    /// request on every partial repository name.
    public static let lookupDelay: Duration = .seconds(1)

    public let editingID: String?
    public var url: String
    public var name: String
    public var sourceChoice: SourceChoice
    public var username: String
    public var accessToken: String
    public var assetFilter: String
    public var bundleID: String
    /// The latest release's programs, for the inputs named by `lookupKey`.
    public private(set) var releasePrograms: ReleasePrograms?
    private var lookupKey = ""
    /// The last name derived from the URL or a chosen program, so it keeps
    /// following them until the user edits the name.
    private var autoFilledName = ""
    /// Whether an existing GitLab entry is being edited: GitLab has no
    /// client, but the entry keeps its choice so editing cannot retype it.
    private let editingGitLab: Bool

    /// An empty dialog for adding a program.
    public init() {
        editingID = nil
        url = ""
        name = ""
        sourceChoice = .automatic
        username = ""
        accessToken = ""
        assetFilter = ""
        bundleID = ""
        editingGitLab = false
    }

    /// The dialog for editing `app`, with its stored key when it has one.
    public init(editing app: TrackedApp, accessToken: String?) {
        editingID = app.id
        url = app.sourceURL
        name = app.name
        sourceChoice = .source(app.sourceType)
        username = app.username ?? ""
        self.accessToken = accessToken ?? ""
        assetFilter = app.assetFilter ?? ""
        bundleID = app.bundleID ?? ""
        editingGitLab = app.sourceType == .gitlab
    }

    public var isEdit: Bool { editingID != nil }

    public var sourceOptions: [SourceChoice] {
        [.automatic, .source(.github), .source(.forgejo)] + (editingGitLab ? [.source(.gitlab)] : [])
    }

    /// Forgejo is self-hosted, so a private instance needs credentials no
    /// other source uses.
    public var needsCredentials: Bool { sourceChoice == .source(.forgejo) }

    // MARK: - Name

    /// Follows the URL with the repository's name, until the user has typed
    /// a name of their own. Editing never renames.
    public mutating func urlDidChange() {
        guard !isEdit else { return }
        guard name.isEmpty || name == autoFilledName else { return }
        if let derived = Self.repositoryName(in: url) {
            name = derived
            autoFilledName = derived
        }
    }

    /// The repository part of an `<host>/<owner>/<repo>` URL, on any host.
    public static func repositoryName(in url: String) -> String? {
        let pattern = "^(?:https?://)?[^/\\s?#]+/[^/\\s?#]+/([^/\\s?#]+)"
        let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        var repo = String(text[range])
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        return repo.isEmpty ? nil : repo
    }

    /// A program name from a release, as a program name: `seance-sync`
    /// becomes `Seance Sync`. Installed programs are looked up by name, so
    /// it should read like the program rather than like a file name.
    public static func displayName(forProgram program: String) -> String {
        program.split(separator: "-", omittingEmptySubsequences: true)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    // MARK: - Programs in the release

    /// Offered only when there is a choice to make.
    public var offeredPrograms: [String] {
        guard let programs = releasePrograms?.programs, programs.count > 1 else { return [] }
        return programs
    }

    /// The offered program the filter names, or "" for none.
    public var chosenProgram: String {
        let typed = assetFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return offeredPrograms.contains(typed) ? typed : ""
    }

    /// What the program goes by without a choice, shown under the picker.
    public var defaultProgramHint: String? {
        guard !offeredPrograms.isEmpty, assetFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let program = releasePrograms?.defaultProgram else { return nil }
        return "Without a choice, Software Update Finder downloads \(program)."
    }

    /// Chooses a program; a name still derived from the URL follows it,
    /// because installed programs are found by name.
    public mutating func chooseProgram(_ program: String) {
        assetFilter = program
        guard !isEdit, !program.isEmpty else { return }
        if name.isEmpty || name == autoFilledName {
            name = Self.displayName(forProgram: program)
            autoFilledName = name
        }
    }

    /// Call after any field changed. A reply for inputs that have changed
    /// since is dropped by `receive`.
    public mutating func lookupChange() -> LookupChange {
        let inputs = [url, sourceChoice.label, needsCredentials ? username : "", needsCredentials ? accessToken : ""]
        let key = inputs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "\u{1F}")
        guard key != lookupKey else { return .unchanged }
        lookupKey = key
        releasePrograms = nil
        guard Self.repositoryName(in: url) != nil else { return .cancel }
        return .lookup(key: key, input: input)
    }

    /// Takes a lookup's reply if it still belongs to the current inputs.
    public mutating func receive(_ programs: ReleasePrograms, forKey key: String) {
        guard key == lookupKey else { return }
        releasePrograms = programs
    }

    // MARK: - Submitting

    /// Why the form cannot be submitted, or nil.
    public var validationError: String? {
        if url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Please enter a repository URL" }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Please enter a program name" }
        return nil
    }

    public var input: SourceInput {
        func trimmedOrNil(_ text: String) -> String? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let sourceType: SourceType?
        switch sourceChoice {
        case .automatic: sourceType = nil
        case .source(let type): sourceType = type
        }
        // Credentials belong to Forgejo only: switching away drops them
        // rather than storing keys nothing will send.
        return SourceInput(url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                           name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                           sourceType: sourceType,
                           username: needsCredentials ? trimmedOrNil(username) : nil,
                           accessToken: needsCredentials ? trimmedOrNil(accessToken) : nil,
                           assetFilter: trimmedOrNil(assetFilter),
                           bundleID: trimmedOrNil(bundleID))
    }
}
