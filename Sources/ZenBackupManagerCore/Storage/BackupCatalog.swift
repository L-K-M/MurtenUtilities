import Foundation

enum BackupCatalog {
    static func scan(profile: ZenProfile, safetyRoot: URL, progress: (Int, Int) -> Void = { _, _ in }) throws -> [BackupRecord] {
        try SessionFiles.validateProfile(profile.directory)
        let fm = FileManager.default
        var candidates: [(URL, BackupRecord.Kind)] = []
        for name in SessionFiles.names {
            let file = profile.directory.appendingPathComponent(name)
            if fm.fileExists(atPath: file.path) { candidates.append((file, .current)) }
        }
        for (folder, kind) in [("zen-sessions-backup", BackupRecord.Kind.automatic), ("sessionstore-backups", .legacy)] {
            let directory = profile.directory.appendingPathComponent(folder)
            if !fm.fileExists(atPath: directory.path) { continue }
            guard directory.standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL else { throw BackupError.unsafePath }
            let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
            for file in files where file.lastPathComponent.contains(".jsonlz4") || file.pathExtension == "baklz4" {
                candidates.append((file, kind))
            }
        }
        for archive in try SafetyArchive.list(root: safetyRoot, profile: profile) {
            for name in SessionFiles.names where archive.manifest.hashes[name] != nil {
                candidates.append((archive.directory.appendingPathComponent(name), .safety))
            }
        }
        var records: [BackupRecord] = []
        for (offset, candidate) in candidates.enumerated() {
            try Task.checkCancellation()
            let record = autoreleasepool { () -> BackupRecord in
                let (file, kind) = candidate
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                do {
                    let data = try SessionFiles.read(file)
                    let preview = try SessionPreview.parse(data)
                    return BackupRecord(file: file, modifiedAt: values?.contentModificationDate ?? .distantPast,
                        bytes: data.count, kind: kind, preview: preview, digest: SessionFiles.digest(data), problem: nil)
                } catch {
                    return BackupRecord(file: file, modifiedAt: values?.contentModificationDate ?? .distantPast,
                        bytes: values?.fileSize ?? 0, kind: kind, preview: nil, digest: nil, problem: error.localizedDescription)
                }
            }
            records.append(record)
            progress(offset + 1, candidates.count)
        }
        return records.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
}
