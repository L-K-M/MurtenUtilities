import Foundation

struct RestoreService {
    let safetyRoot: URL
    var isZenRunning: () -> Bool
    /// Injection point for failure/rollback tests. Production uses atomic writes.
    var write: (Data, URL) throws -> Void = { try SessionFiles.write($0, to: $1) }

    func restore(_ backup: BackupRecord, to profile: ZenProfile) throws -> SafetyArchive {
        guard backup.canRestore, let digest = backup.digest else {
            throw BackupError.invalid("Select a readable backup before restoring.")
        }
        try SessionFiles.validateProfile(profile.directory)
        guard !isZenRunning() else { throw BackupError.zenRunning }
        let lock = try ProfileLock(directory: profile.directory)
        defer { withExtendedLifetime(lock) {} }
        let data = try SessionFiles.read(backup.file)
        guard SessionFiles.digest(data) == digest else { throw BackupError.changed }
        let preview = try SessionPreview.parse(data)
        guard !isZenRunning() else { throw BackupError.zenRunning }
        let safety = try SafetyArchive.create(profile: profile, root: safetyRoot, reason: "Before restore")
        do {
            guard !isZenRunning() else { throw BackupError.zenRunning }
            switch preview.format {
            case .zen:
                try write(data, profile.directory.appendingPathComponent("zen-sessions.jsonlz4"))
            case .firefox:
                // Zen's documented legacy migration: remove the modern session,
                // install sessionstore.jsonlz4, and let Zen import it at startup.
                try write(data, profile.directory.appendingPathComponent("sessionstore.jsonlz4"))
                let modern = profile.directory.appendingPathComponent("zen-sessions.jsonlz4")
                if FileManager.default.fileExists(atPath: modern.path) { try FileManager.default.removeItem(at: modern) }
            }
            let target = profile.directory.appendingPathComponent(preview.format == .zen ? "zen-sessions.jsonlz4" : "sessionstore.jsonlz4")
            guard SessionFiles.digest(try SessionFiles.read(target)) == digest else { throw BackupError.invalid("Restored data could not be verified.") }
        } catch {
            try rollback(safety, profile: profile, originalError: error)
        }
        return safety
    }

    func undo(_ archive: SafetyArchive, profile: ZenProfile) throws -> SafetyArchive {
        try SessionFiles.validateProfile(profile.directory)
        guard !isZenRunning() else { throw BackupError.zenRunning }
        let lock = try ProfileLock(directory: profile.directory)
        defer { withExtendedLifetime(lock) {} }
        let contents = try archive.verifiedContents(profile: profile)
        let safety = try SafetyArchive.create(profile: profile, root: safetyRoot, reason: "Before undo")
        guard !isZenRunning() else { throw BackupError.zenRunning }
        do { try apply(contents, profile: profile, writer: write) }
        catch { try rollback(safety, profile: profile, originalError: error) }
        return safety
    }

    private func rollback(_ archive: SafetyArchive, profile: ZenProfile, originalError: Error) throws {
        do {
            try apply(archive.verifiedContents(profile: profile), profile: profile, writer: SessionFiles.write)
        } catch {
            throw BackupError.invalid("Restore failed and rollback could not finish. Your original files are preserved at \(archive.directory.path). Restore error: \(originalError.localizedDescription) Rollback error: \(error.localizedDescription)")
        }
        throw BackupError.invalid("No restore was completed; original session files were put back. \(originalError.localizedDescription)")
    }

    private func apply(_ contents: [String: Data], profile: ZenProfile, writer: (Data, URL) throws -> Void) throws {
        try SessionFiles.validateProfile(profile.directory)
        for name in SessionFiles.names {
            let target = profile.directory.appendingPathComponent(name)
            if let data = contents[name] {
                try writer(data, target)
                guard try SessionFiles.read(target) == data else { throw BackupError.invalid("Could not verify \(name).") }
            } else if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
        }
    }
}
