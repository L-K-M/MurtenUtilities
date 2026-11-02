import Foundation

struct SafetyArchive: Sendable {
    struct Manifest: Codable, Sendable {
        let version: Int
        let profilePath: String
        let createdAt: Date
        let reason: String
        let hashes: [String: String]
    }
    let directory: URL
    let manifest: Manifest

    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ZenBackupManager/Safety Copies", isDirectory: true)
    }

    static func create(profile: ZenProfile, root: URL, reason: String) throws -> SafetyArchive {
        try SessionFiles.validateProfile(profile.directory)
        let fm = FileManager.default
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard root.standardizedFileURL == root.resolvingSymlinksInPath().standardizedFileURL else { throw BackupError.unsafePath }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Incomplete archives have no manifest, so they never become undo candidates.
        var hashes: [String: String] = [:]
        for name in SessionFiles.names {
            let source = profile.directory.appendingPathComponent(name)
            guard fm.fileExists(atPath: source.path) else { continue }
            let data = try SessionFiles.read(source)
            let target = directory.appendingPathComponent(name)
            try SessionFiles.write(data, to: target)
            let digest = SessionFiles.digest(data)
            guard SessionFiles.digest(try SessionFiles.read(target)) == digest else {
                throw BackupError.invalid("The safety copy could not be verified. Nothing was restored.")
            }
            hashes[name] = digest
        }
        let manifest = Manifest(version: 1, profilePath: profile.directory.path, createdAt: Date(), reason: reason, hashes: hashes)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try SessionFiles.write(try encoder.encode(manifest), to: directory.appendingPathComponent("manifest.json"))
        return SafetyArchive(directory: directory, manifest: manifest)
    }

    static func list(root: URL, profile: ZenProfile) throws -> [SafetyArchive] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        guard root.standardizedFileURL == root.resolvingSymlinksInPath().standardizedFileURL else { throw BackupError.unsafePath }
        let directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        return directories.compactMap { directory in
            guard let data = try? SessionFiles.read(directory.appendingPathComponent("manifest.json")),
                  let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
                  manifest.version == 1, manifest.profilePath == profile.directory.path,
                  Set(manifest.hashes.keys).isSubset(of: Set(SessionFiles.names)) else { return nil }
            return SafetyArchive(directory: directory, manifest: manifest)
        }.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
    }

    func verifiedContents(profile: ZenProfile) throws -> [String: Data] {
        guard manifest.version == 1, manifest.profilePath == profile.directory.path,
              Set(manifest.hashes.keys).isSubset(of: Set(SessionFiles.names)) else { throw BackupError.unsafePath }
        var result: [String: Data] = [:]
        for (name, digest) in manifest.hashes {
            let data = try SessionFiles.read(directory.appendingPathComponent(name))
            guard SessionFiles.digest(data) == digest else { throw BackupError.invalid("The safety copy has changed and cannot be used for undo.") }
            result[name] = data
        }
        return result
    }
}
