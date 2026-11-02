import Foundation

/// Reads Git's worktree registrations without running Git or walking hidden trees.
/// Both sides of each registration must agree before the scanner may visit it.
package enum GitWorktrees {

    // MARK: - Discovery

    /// `isAllowed` vets every path read from Git's metadata before anything is
    /// looked up there: background scans pass one that refuses privacy-protected
    /// folders, so a registration cannot lead them into ~/Documents.
    package static func registeredWorktrees(in repository: URL,
                                    fileManager: FileManager = .default,
                                    isAllowed: (String) -> Bool = { _ in true }) -> [URL] {
        let gitFile = repository.appendingPathComponent(".git")
        guard let common = commonDirectory(for: gitFile, isAllowed: isAllowed) else { return [] }
        let registrations = common.appendingPathComponent("worktrees")
        guard isDirectoryWithoutSymlinks(registrations),
              let entries = try? fileManager.contentsOfDirectory(
                at: registrations, includingPropertiesForKeys: nil) else { return [] }

        return entries.compactMap { registration in
            guard isDirectoryWithoutSymlinks(registration),
                  registrationCommonDirectory(registration, isAllowed: isAllowed)?.path == common.path,
                  let gitFile = registeredGitFile(registration, isAllowed: isAllowed),
                  gitFile.lastPathComponent == ".git",
                  pointer(in: gitFile, isAllowed: isAllowed)?.path == canonical(registration).path else { return nil }
            let worktree = gitFile.deletingLastPathComponent()
            guard isDirectoryWithoutSymlinks(worktree) else { return nil }
            return canonical(worktree)
        }
    }

    /// Checking every component prevents a registration from bypassing the walk's
    /// no-symlink rule through a hidden parent directory or a metadata file.
    package static func hasNoSymlinkComponents(_ url: URL) -> Bool {
        var current = URL(fileURLWithPath: "/")
        // standardizedFileURL rewrites /private/var to /var on macOS, introducing
        // a symlink into an already canonical path. Inspect the given spelling.
        for component in url.pathComponents.dropFirst() {
            current.appendPathComponent(component)
            guard let values = try? current.resourceValues(forKeys: [.isSymbolicLinkKey]),
                  values.isSymbolicLink == false else { return false }
        }
        return true
    }

    // MARK: - Reciprocal metadata

    private static func commonDirectory(for gitFile: URL, isAllowed: (String) -> Bool) -> URL? {
        if isDirectoryWithoutSymlinks(gitFile) { return canonical(gitFile) }

        // A linked worktree's .git file points at common/worktrees/<id>. Its
        // commondir and gitdir must lead back to the same common directory and file.
        guard let registration = pointer(in: gitFile, isAllowed: isAllowed),
              let common = registrationCommonDirectory(registration, isAllowed: isAllowed),
              registeredGitFile(registration, isAllowed: isAllowed)?.path == canonical(gitFile).path else { return nil }
        return common
    }

    private static func registrationCommonDirectory(_ registration: URL, isAllowed: (String) -> Bool) -> URL? {
        guard isDirectoryWithoutSymlinks(registration),
              registration.deletingLastPathComponent().lastPathComponent == "worktrees",
              let value = line(in: registration.appendingPathComponent("commondir")),
              let common = resolve(value, relativeTo: registration, isAllowed: isAllowed),
              isDirectoryWithoutSymlinks(common),
              canonical(common).path == canonical(registration.deletingLastPathComponent()
                .deletingLastPathComponent()).path else { return nil }
        return canonical(common)
    }

    private static func registeredGitFile(_ registration: URL, isAllowed: (String) -> Bool) -> URL? {
        guard let value = line(in: registration.appendingPathComponent("gitdir")),
              let gitFile = resolve(value, relativeTo: registration, isAllowed: isAllowed),
              isRegularFileWithoutSymlinks(gitFile) else { return nil }
        return canonical(gitFile)
    }

    private static func pointer(in gitFile: URL, isAllowed: (String) -> Bool) -> URL? {
        guard let value = line(in: gitFile), value.hasPrefix("gitdir: ") else { return nil }
        let path = String(value.dropFirst("gitdir: ".count))
        guard !path.isEmpty else { return nil }
        guard let registration = resolve(path, relativeTo: gitFile.deletingLastPathComponent(),
                                         isAllowed: isAllowed),
              isDirectoryWithoutSymlinks(registration) else { return nil }
        return canonical(registration)
    }

    // MARK: - Filesystem checks

    private static func line(in file: URL) -> String? {
        guard isRegularFileWithoutSymlinks(file),
              let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        // Metadata consists of one path. Bound reads so malformed registrations
        // cannot make a scan load an arbitrary large file into memory.
        guard let data = try? handle.read(upToCount: 8_193), data.count <= 8_192,
              var value = String(data: data, encoding: .utf8) else { return nil }
        if value.hasSuffix("\n") { value.removeLast() }
        if value.hasSuffix("\r") { value.removeLast() }
        guard !value.isEmpty, !value.contains("\n"), !value.contains("\r"),
              !value.contains("\0") else { return nil }
        return value
    }

    private static func resolve(_ path: String, relativeTo directory: URL,
                                isAllowed: (String) -> Bool) -> URL? {
        let absolutePath = path.hasPrefix("/") ? path : directory.path + "/" + path
        let url = URL(fileURLWithPath: absolutePath)
        // Lexical, before the first lstat: `..` segments are folded so they cannot
        // walk a refused path past the filter. (standardizedFileURL would also
        // drop /private and miss roots spelled with it.)
        guard isAllowed(ProtectedLocations.lexicallyNormalized(absolutePath)),
              hasNoSymlinkComponents(url) else { return nil }
        return canonical(url)
    }

    private static func isDirectoryWithoutSymlinks(_ url: URL) -> Bool {
        hasNoSymlinkComponents(url)
            && (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    private static func isRegularFileWithoutSymlinks(_ url: URL) -> Bool {
        hasNoSymlinkComponents(url)
            && (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
    }

    private static func canonical(_ url: URL) -> URL {
        if let path = (try? url.resourceValues(forKeys: [.canonicalPathKey]))?.canonicalPath {
            return URL(fileURLWithPath: path)
        }
        return url.standardizedFileURL
    }
}
