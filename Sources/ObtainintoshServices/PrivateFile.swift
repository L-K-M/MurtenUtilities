import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import ObtainintoshCore

/// Owner-only files and folders, written atomically.
enum PrivateFile {
    static let directoryMode: mode_t = 0o700
    static let fileMode: mode_t = 0o600

    /// Creates the folder owner-only, and tightens it if something left it
    /// readable by others.
    static func prepareDirectory(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: directoryMode)], ofItemAtPath: url.path)
        } catch {
            throw ObtainintoshError("Failed to create the folder \(url.path): \(error.localizedDescription)")
        }
    }

    static func tighten(_ url: URL) throws {
        do {
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: fileMode)], ofItemAtPath: url.path)
        } catch {
            throw ObtainintoshError("Failed to secure \(url.lastPathComponent)")
        }
    }

    /// Writes through a fresh sibling and renames it into place.
    ///
    /// The scratch file is created exclusively under a unique name, so a
    /// symbolic link at a predictable temporary path cannot redirect the
    /// write, and it is born owner-only rather than tightened afterwards.
    static func writeAtomically(_ data: Data, to destination: URL) throws {
        var temporary: URL
        var descriptor: Int32
        repeat {
            temporary = destination.deletingLastPathComponent()
                .appendingPathComponent("\(destination.lastPathComponent).\(UUID().uuidString.lowercased()).tmp")
            descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, fileMode)
        } while descriptor < 0 && errno == EEXIST
        guard descriptor >= 0 else { throw ObtainintoshError("Failed to write temp file") }

        var published = false
        defer {
            if !published { unlink(temporary.path) }
        }

        // The mode applies only at creation and umask can clear bits from it.
        let written: Bool = data.withUnsafeBytes { buffer in
            guard fchmod(descriptor, fileMode) == 0 else { return false }
            var offset = 0
            while offset < buffer.count {
                let result = write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                if result < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += result
            }
            return fsync(descriptor) == 0
        }
        close(descriptor)
        guard written else { throw ObtainintoshError("Failed to write temp file") }

        guard rename(temporary.path, destination.path) == 0 else {
            throw ObtainintoshError("Failed to rename temp file: \(String(cString: strerror(errno)))")
        }
        published = true
    }

    /// Moves an unreadable file aside and returns where it went, never over
    /// an earlier backup: `.corrupt-backup`, `.corrupt-backup.1`, … A hard
    /// link fails instead of clobbering, which keeps the search safe.
    static func backUpCorruptFile(_ url: URL) throws -> URL {
        var index = 0
        while true {
            let suffix = index == 0 ? ".corrupt-backup" : ".corrupt-backup.\(index)"
            let backup = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + suffix)
            if link(url.path, backup.path) == 0 {
                guard unlink(url.path) == 0 else {
                    throw ObtainintoshError("Failed to remove \(url.lastPathComponent) after backing it up")
                }
                return backup
            }
            guard errno == EEXIST else {
                throw ObtainintoshError("Failed to back up \(url.lastPathComponent): \(String(cString: strerror(errno)))")
            }
            index += 1
        }
    }
}
