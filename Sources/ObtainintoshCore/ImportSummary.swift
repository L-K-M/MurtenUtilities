import Foundation

/// What an import did with a file's entries, and how the pane words it.
public struct ImportSummary: Equatable, Sendable {
    public var fileName: String
    public var added: Int
    /// Entries whose repository was tracked already, left as they were.
    public var duplicates: Int
    public var rejected: [AppList.RejectedEntry]
    /// Added Forgejo programs that came with a username but no application
    /// key: an export never writes keys.
    public var missingKeys: Int

    public init(fileName: String, added: Int, duplicates: Int, rejected: [AppList.RejectedEntry] = [],
                missingKeys: Int = 0) {
        self.fileName = fileName
        self.added = added
        self.duplicates = duplicates
        self.rejected = rejected
        self.missingKeys = missingKeys
    }

    /// One line saying what the import added and what it left alone.
    /// Re-importing a backup is the everyday case, and "Imported 0 programs"
    /// reads like a failure when it is the expected outcome.
    public var message: String {
        let added = self.added == 0
            ? "No programs were imported from \(fileName)"
            : "Imported \(Self.plural(self.added, "program")) from \(fileName)"
        guard duplicates > 0 else { return added }
        let duplicates = self.duplicates == 1 ? "1 was already tracked" : "\(self.duplicates) were already tracked"
        return "\(added) (\(duplicates))"
    }

    public var missingKeysMessage: String? {
        guard missingKeys > 0 else { return nil }
        let programs = Self.plural(missingKeys, "imported Forgejo program")
        let keys = missingKeys == 1 ? "needs its application key" : "need their application keys"
        let action = missingKeys == 1 ? "Edit the program to add it." : "Edit each program to add its key."
        return "\(programs) \(keys) — keys are never written to an export. \(action)"
    }

    /// Names the entries the import turned away, bounded so a file full of
    /// them does not produce a message the height of the window.
    public var rejectedMessage: String? {
        guard !rejected.isEmpty else { return nil }
        let shown = 3
        let details = rejected.prefix(shown).map { "\($0.label): \($0.reason)" }.joined(separator: "; ")
        let remaining = rejected.count - shown
        let more = remaining > 0 ? "; and \(Self.plural(remaining, "more entry", "more entries"))" : ""
        let skipped = Self.plural(rejected.count, "entry", "entries")
        return "\(skipped) of \(fileName) could not be imported — \(details)\(more)"
    }

    public static func plural(_ count: Int, _ singular: String, _ pluralForm: String? = nil) -> String {
        "\(count) \(count == 1 ? singular : (pluralForm ?? singular + "s"))"
    }
}
