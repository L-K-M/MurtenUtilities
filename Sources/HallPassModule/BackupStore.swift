import Foundation
import HallPassCore

struct BackupStore {
    private let root: URL?

    init(root: URL? = nil) {
        self.root = root
    }

    func readBackup(at url: URL) throws -> NetworkConfiguration {
        try ConfigurationBackup.decode(read(url, limit: ConfigurationBackup.maximumDataSize)).configuration
    }

    func export(_ configuration: NetworkConfiguration, to url: URL) throws {
        try ConfigurationBackup(configuration: configuration).encoded().write(to: url, options: .atomic)
    }

    func automaticBackup(_ configuration: NetworkConfiguration) throws -> URL {
        let date = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = try backupsDirectory().appendingPathComponent("HallPass-\(date)-\(UUID().uuidString.prefix(8)).json")
        try writePrivate(ConfigurationBackup(configuration: configuration).encoded(), to: url)
        return url
    }

    func loadRecovery() throws -> DraftRecovery? {
        let url = try recoveryURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try DraftRecovery.decode(read(url, limit: DraftRecovery.maximumDataSize))
    }

    func saveRecovery(_ recovery: DraftRecovery) throws {
        try writePrivate(recovery.encoded(), to: recoveryURL())
    }

    func preserveFailedRecovery() throws -> URL {
        let original = try recoveryURL()
        let preserved = try backupsDirectory().appendingPathComponent("HallPass-Draft-\(UUID().uuidString).json")
        try FileManager.default.moveItem(at: original, to: preserved)
        return preserved
    }

    func removeRecovery() throws {
        let url = try recoveryURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func backupsDirectory() throws -> URL {
        try directory().appendingPathComponent("Backups", isDirectory: true).creatingPrivateDirectory()
    }

    private func recoveryURL() throws -> URL {
        try directory().appendingPathComponent("Draft.json")
    }

    private func directory() throws -> URL {
        if let root { return try root.creatingPrivateDirectory() }
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return try support.appendingPathComponent("HallPass", isDirectory: true).creatingPrivateDirectory()
    }

    private func writePrivate(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func read(_ url: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw ConfigurationError.unsupportedBackup }
        return data
    }
}

private extension URL {
    func creatingPrivateDirectory() throws -> URL {
        try FileManager.default.createDirectory(at: self, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return self
    }
}
