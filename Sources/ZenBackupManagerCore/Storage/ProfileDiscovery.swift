import Foundation

public enum ProfileDiscovery {
    public static var zenRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/zen", isDirectory: true)
    }

    public static func discover(root: URL = zenRoot) throws -> [ZenProfile] {
        let ini = root.appendingPathComponent("profiles.ini")
        guard FileManager.default.fileExists(atPath: ini.path) else { return [] }
        let text = try String(contentsOf: ini, encoding: .utf8)
        let sections = parseINI(text)
        let installDefaults = Set(sections.filter { $0.key.hasPrefix("Install") }.compactMap { $0.value["Default"] })
        var seen = Set<String>()
        return sections.filter { $0.key.hasPrefix("Profile") }.compactMap { _, values in
            guard let path = values["Path"], !path.isEmpty else { return nil }
            let directory = (values["IsRelative"] == "0" ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)).standardizedFileURL
            guard seen.insert(directory.path).inserted, FileManager.default.fileExists(atPath: directory.appendingPathComponent("prefs.js").path) else { return nil }
            return ZenProfile(name: values["Name"] ?? directory.lastPathComponent, directory: directory,
                isDefault: installDefaults.isEmpty ? values["Default"] == "1" : installDefaults.contains(path))
        }.sorted { $0.isDefault != $1.isDefault ? $0.isDefault : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The directory of every profile profiles.ini names, readable or not,
    /// standardized like `ZenProfile.id`. `discover` keeps only those with a
    /// prefs.js; the rest still exist as far as the watcher can tell.
    public static func listedDirectories(root: URL = zenRoot) throws -> Set<String> {
        let ini = root.appendingPathComponent("profiles.ini")
        guard FileManager.default.fileExists(atPath: ini.path) else { return [] }
        let text = try String(contentsOf: ini, encoding: .utf8)
        return Set(parseINI(text).filter { $0.key.hasPrefix("Profile") }.compactMap { _, values -> String? in
            guard let path = values["Path"], !path.isEmpty else { return nil }
            let directory = values["IsRelative"] == "0" ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)
            return directory.standardizedFileURL.path
        })
    }

    static func parseINI(_ text: String) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        var section = ""
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") { section = String(line.dropFirst().dropLast()); continue }
            guard !section.isEmpty, let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            result[section, default: [:]][key] = value
        }
        return result
    }
}
