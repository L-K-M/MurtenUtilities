import Foundation

/// Export and import of the tracked-program list as a JSON file, compatible
/// with the standalone app's `.obtainintosh` files in both directions.
///
/// The file carries what identifies each program (name, forge, repository
/// URL, program filter, Forgejo username) and none of the state Obtainintosh
/// recomputes. Application keys are never written: the file is meant to be
/// shared. An import adds what is not tracked yet and never removes or
/// overwrites anything.
public enum AppList {
    /// The extension an exported list carries, so the open panel can filter
    /// for it.
    public static let fileExtension = "obtainintosh"
    public static let fileTypeLabel = "Obtainintosh program list"
    /// Files bigger than this are refused before they are read: a list of
    /// thousands of programs is well under a megabyte.
    public static let maximumFileSize: UInt64 = 16 * 1024 * 1024

    /// Marks a JSON document as a program list.
    static let format = "obtainintosh-app-list"
    /// Written when an entry tracks one program of a multi-program release,
    /// and the newest this build reads: a reader without filters would track
    /// the wrong program for such an entry.
    static let formatVersion: UInt32 = 2
    /// Written when no entry has a filter, so older readers still accept it.
    static let formatVersionWithoutAssetFilters: UInt32 = 1

    // MARK: - Export

    private struct File: Codable {
        var format: String
        var formatVersion: UInt32
        var exportedAt: String
        var exportedBy: String
        var apps: [ExportedApp]

        private enum CodingKeys: String, CodingKey {
            case format
            case formatVersion = "format_version"
            case exportedAt = "exported_at"
            case exportedBy = "exported_by"
            case apps
        }

        init(format: String, formatVersion: UInt32, exportedAt: String, exportedBy: String, apps: [ExportedApp]) {
            self.format = format
            self.formatVersion = formatVersion
            self.exportedAt = exportedAt
            self.exportedBy = exportedBy
            self.apps = apps
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            format = try container.decode(String.self, forKey: .format)
            formatVersion = try container.decode(UInt32.self, forKey: .formatVersion)
            exportedAt = try container.decodeIfPresent(String.self, forKey: .exportedAt) ?? ""
            exportedBy = try container.decodeIfPresent(String.self, forKey: .exportedBy) ?? ""
            apps = try container.decode([ExportedApp].self, forKey: .apps)
        }
    }

    /// The file contents for the tracked list. Done before any panel is
    /// shown, so a failure never asks the user for a path first.
    public static func render(_ apps: [TrackedApp], exportedAt: String, exportedBy: String) throws -> String {
        let version = apps.contains { $0.assetFilter != nil } ? formatVersion : formatVersionWithoutAssetFilters
        let file = File(format: format, formatVersion: version, exportedAt: exportedAt, exportedBy: exportedBy,
                        apps: apps.map(ExportedApp.init))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(file)
            return String(decoding: data, as: UTF8.self) + "\n"
        } catch {
            throw ObtainintoshError("Failed to serialize the program list: \(error.localizedDescription)")
        }
    }

    // MARK: - Import

    /// The lenient first pass: only the marker and the version, each read on
    /// its own, so a version written as `"1"` is reported as a version
    /// problem rather than hiding the marker next to it.
    private struct Header: Decodable {
        var format: String?
        var formatVersion: UInt32?

        private enum CodingKeys: String, CodingKey {
            case format
            case formatVersion = "format_version"
        }

        init(from decoder: Decoder) throws {
            // A document that is not an object at all is simply one without
            // either field.
            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            format = try? container.decode(String.self, forKey: .format)
            formatVersion = try? container.decode(UInt32.self, forKey: .formatVersion)
        }
    }

    /// The entries a file lists, refusing anything that is not a program
    /// list this build understands.
    public static func parse(_ contents: String) throws -> [ExportedApp] {
        // Some editors save UTF-8 with a byte-order mark; a hand-edited list
        // should not fail over an invisible first character.
        let text = contents.hasPrefix("\u{feff}") ? String(contents.dropFirst()) : contents
        let data = Data(text.utf8)
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw ObtainintoshError("The file is not valid JSON: \(error.localizedDescription)")
        }

        let header = try? JSONDecoder().decode(Header.self, from: data)
        guard header?.format == format else {
            throw ObtainintoshError("The file is not an Obtainintosh program list")
        }
        guard let version = header?.formatVersion else {
            throw ObtainintoshError("The file does not say which program list format it uses")
        }
        guard version <= formatVersion else {
            throw ObtainintoshError("The file was written by a newer version of Obtainintosh (program list format "
                + "\(version); this version reads format \(formatVersion) and older). Update Murten Utilities to "
                + "import it.")
        }

        // Structural problems in an entry fail the whole file, naming where:
        // more useful for a hand-edited file than importing around it.
        do {
            return try JSONDecoder().decode(File.self, from: data).apps
        } catch let error as DecodingError {
            throw ObtainintoshError("The program list could not be read: \(describe(error))")
        } catch {
            throw ObtainintoshError("The program list could not be read: \(error.localizedDescription)")
        }
    }

    /// An entry that could not become a tracked program, and why.
    public struct RejectedEntry: Equatable, Sendable {
        /// The entry's name, or its position when it has none.
        public let label: String
        public let reason: String

        public init(label: String, reason: String) {
            self.label = label
            self.reason = reason
        }
    }

    /// A file's entries sorted into programs ready to add (without ids) and
    /// entries that were turned away.
    public struct ImportPlan: Equatable, Sendable {
        public var apps: [TrackedApp] = []
        public var rejected: [RejectedEntry] = []
    }

    /// Applies the Add Program dialog's rules to each entry: a name and URL
    /// are required, the forge is detected when not named, and credentials
    /// are kept only for a forge that uses them. Duplicates are decided by
    /// the store, where the answer cannot go stale.
    public static func planImport(_ entries: [ExportedApp]) -> ImportPlan {
        var plan = ImportPlan()
        for (index, entry) in entries.enumerated() {
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = name.isEmpty ? "entry \(index + 1)" : boundedExcerpt(name)
            do {
                plan.apps.append(try app(named: name, from: entry))
            } catch {
                plan.rejected.append(RejectedEntry(label: label, reason: "\(error)"))
            }
        }
        return plan
    }

    private static func app(named name: String, from entry: ExportedApp) throws -> TrackedApp {
        guard !name.isEmpty else { throw ObtainintoshError("The program name is empty") }
        let sourceURL = entry.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceURL.isEmpty else { throw ObtainintoshError("The repository URL is empty") }
        guard let sourceType = entry.sourceType ?? RepositoryURL.detectSourceType(sourceURL) else {
            throw ObtainintoshError("Unsupported source URL. Add \"source_type\": \"forgejo\" to the entry if "
                + "\(boundedExcerpt(sourceURL)) is a Forgejo instance.")
        }
        // Canonical, like the dialog stores it, so the duplicate check sees
        // "Seance" and "seance" as the same program.
        let assetFilter = try AssetFilter.canonicalize(entry.assetFilter ?? "")
        let credentials = ForgeCredentials.forSource(sourceType, username: entry.username, token: entry.accessToken)
        let bundleID = entry.bundleID?.trimmingCharacters(in: .whitespacesAndNewlines)

        return TrackedApp(name: name, sourceType: sourceType, sourceURL: sourceURL, assetFilter: assetFilter,
                          username: credentials.username, accessToken: credentials.token,
                          bundleID: bundleID?.isEmpty == false ? bundleID : nil)
    }

    /// Collapses whitespace and caps the length of a value quoted back from
    /// a file that may have been shared around.
    static func boundedExcerpt(_ text: String) -> String {
        let maximumCharacters = 60
        let normalized = text.collapsingWhitespace()
        if normalized.count <= maximumCharacters { return normalized }
        return String(normalized.prefix(maximumCharacters - 1)) + "…"
    }

    /// A Forgejo program that arrived with a username but no application key,
    /// the shape every private-instance entry has after a round trip through
    /// a file. Worth telling the user, or the next check fails on credentials.
    public static func isMissingApplicationKey(_ app: TrackedApp) -> Bool {
        app.sourceType == .forgejo && app.username != nil && app.accessToken == nil && !app.hasStoredAccessToken
    }

    // MARK: - File names

    /// The name the save panel proposes: dated, so successive exports sit
    /// side by side instead of replacing each other.
    public static func suggestedFileName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "Obtainintosh Programs \(formatter.string(from: date)).\(fileExtension)"
    }

    /// Gives a chosen save path the list's extension when it has none. An
    /// extension typed deliberately (`list.json`) is left alone; a trailing
    /// dot is no extension and is not kept either.
    public static func withDefaultExtension(_ url: URL) -> URL {
        let name = url.lastPathComponent
        guard !name.isEmpty, name != "/" else { return url }
        if let dot = name.lastIndex(of: "."), dot != name.startIndex, name.index(after: dot) != name.endIndex {
            return url
        }
        let trimmed = name.trimmingSuffixRepeatedly(".")
        guard !trimmed.isEmpty else { return url }
        return url.deletingLastPathComponent().appendingPathComponent("\(trimmed).\(fileExtension)")
    }

    /// The file name shown in messages.
    public static func displayName(_ url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }

    // MARK: - Decoding errors

    /// A decoding failure in words, with where it happened:
    /// "missing field `apps`", "unknown variant `gihub` … at apps[0].source_type".
    static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "missing field `\(key.stringValue)`" + location(context.codingPath)
        case .dataCorrupted(let context):
            return context.debugDescription + location(context.codingPath)
        case .typeMismatch(let type, let context):
            return "invalid type, expected \(type)" + location(context.codingPath)
        case .valueNotFound(let type, let context):
            return "missing \(type) value" + location(context.codingPath)
        @unknown default:
            return "\(error)"
        }
    }

    private static func location(_ path: [CodingKey]) -> String {
        guard !path.isEmpty else { return "" }
        var rendered = ""
        for key in path {
            if let index = key.intValue {
                rendered += "[\(index)]"
            } else {
                rendered += rendered.isEmpty ? key.stringValue : "." + key.stringValue
            }
        }
        return " at \(rendered)"
    }
}
