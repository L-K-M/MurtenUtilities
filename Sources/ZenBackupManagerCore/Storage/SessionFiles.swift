import Foundation
import CryptoKit
import Darwin

/// Only these two files are ever replaced. Other profile data is never edited.
enum SessionFiles {
    static let names = ["zen-sessions.jsonlz4", "sessionstore.jsonlz4"]
    static let maximumSize = MozillaLZ4.maximumSize

    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func validateProfile(_ directory: URL) throws {
        guard directory.isFileURL, directory.standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL,
              try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
              FileManager.default.fileExists(atPath: directory.appendingPathComponent("prefs.js").path) else {
            throw BackupError.unsafePath
        }
        for name in names { try validateDestination(directory.appendingPathComponent(name)) }
    }

    static func validateDestination(_ file: URL) throws {
        let values = try? file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard values?.isSymbolicLink != true else { throw BackupError.unsafePath }
        if FileManager.default.fileExists(atPath: file.path), values?.isRegularFile != true { throw BackupError.unsafePath }
        guard file.standardizedFileURL == file.resolvingSymlinksInPath().standardizedFileURL else { throw BackupError.unsafePath }
    }

    static func read(_ file: URL) throws -> Data {
        try validateDestination(file)
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size >= 0, size <= maximumSize else {
            throw BackupError.invalid("The session file is unreadable or larger than 256 MB.")
        }
        let data = try Data(contentsOf: file)
        guard data.count <= maximumSize else { throw BackupError.invalid("The session file grew beyond the size limit.") }
        return data
    }

    static func write(_ data: Data, to file: URL) throws {
        try validateDestination(file)
        let temporary = file.deletingLastPathComponent().appendingPathComponent(".zen-backup-" + UUID().uuidString)
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor); try? FileManager.default.removeItem(at: temporary) }
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), data.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                offset += count
            }
        }
        guard fsync(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        try validateDestination(file)
        guard rename(temporary.path, file.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
