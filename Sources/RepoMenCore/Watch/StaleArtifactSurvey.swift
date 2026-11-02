import Foundation

/// Why background work did not scan a watched folder.
package enum WatchRootRefusal: Equatable, Sendable {
    /// Inside a privacy-protected location (`ProtectedLocations`); scanning it
    /// could raise a prompt nobody asked for.
    case protected(root: String)
    /// The folder no longer exists.
    case missing
    /// The folder exists but cannot be listed.
    case unreadable(permissionDenied: Bool, reason: String)
    /// Its symbolic links do not resolve.
    case unresolvable
}

/// What one watched folder holds that its idle threshold calls stale.
package struct StaleArtifactTotals: Equatable, Sendable {
    package var bytes: Int64
    package var count: Int

    package init(bytes: Int64 = 0, count: Int = 0) {
        self.bytes = bytes
        self.count = count
    }
}

/// The scan both kinds of unattended work share: the suite's background check
/// (which only reports totals) and armed auto-trash (which trashes what this
/// returns, through `Reclaimer`). It reads the file system and never writes it.
///
/// Background scans stay out of privacy-protected locations twice over: a root
/// inside one is refused before anything is read, and a root that contains one
/// (say, the whole home folder) walks around it.
package enum StaleArtifactSurvey {

    /// Splits `folders` into the ones a background scan may read and the reasons
    /// for the rest. Only enabled folders are considered.
    package static func admit(_ folders: [WatchedFolder],
                              protectedRoots: [String] = ProtectedLocations.current,
                              fileManager: FileManager = .default,
                              readLink: (String) -> String? = ProtectedLocations.liveReadLink)
        -> (admitted: [WatchedFolder], refused: [String: WatchRootRefusal]) {
        var admitted: [WatchedFolder] = []
        var refused: [String: WatchRootRefusal] = [:]

        for folder in folders where folder.isEnabled {
            switch ProtectedLocations.classify(folder.path, roots: protectedRoots, readLink: readLink) {
            case .protected(let root):
                refused[folder.path] = .protected(root: root)
                continue
            case .unresolvable:
                refused[folder.path] = .unresolvable
                continue
            case .allowed:
                break
            }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                refused[folder.path] = .missing
                continue
            }
            // The walk swallows listing errors (a scan reports what it can see);
            // for the root itself that would read as "nothing stale".
            do {
                _ = try fileManager.contentsOfDirectory(atPath: folder.path)
                admitted.append(folder)
            } catch {
                refused[folder.path] = .unreadable(permissionDenied: isPermissionError(error),
                                                   reason: error.localizedDescription)
            }
        }
        return (admitted, refused)
    }

    /// Scans `roots`, measures what it finds, and returns the items idle past
    /// their governing folder's threshold, keyed by that folder's path. The
    /// governing folder is the deepest enabled one in `folders`
    /// (`WatchEngine.governingFolder`), so a nested watch keeps its own threshold.
    /// nil when the task was cancelled: a partial walk proves nothing.
    package static func staleItems(in roots: [WatchedFolder],
                                   governedBy folders: [WatchedFolder],
                                   excludedPaths: Set<String>,
                                   enabledKinds: Set<ArtifactKind>,
                                   protectedRoots: [String] = ProtectedLocations.current,
                                   now: Date = Date(),
                                   sizerWidth: Int = 4) async -> [String: [CleanableItem]]? {
        guard !roots.isEmpty else { return [:] }
        let config = ScanConfiguration(
            roots: roots.map { URL(fileURLWithPath: $0.path) },
            excludedPaths: excludedPaths,
            enabledKinds: enabledKinds,
            protectedRoots: protectedRoots)
        let found = Scanner.scan(config)
        guard !Task.isCancelled else { return nil }

        let measured = await measure(found, width: sizerWidth)
        guard !Task.isCancelled else { return nil }

        let eligible = WatchEngine.eligibleItems(items: measured, folders: folders, now: now)
        var byRoot: [String: [CleanableItem]] = [:]
        for item in eligible {
            guard let folder = WatchEngine.governingFolder(for: item.path, folders: folders) else { continue }
            byRoot[folder.path, default: []].append(item)
        }
        return byRoot
    }

    package static func totals(of items: [CleanableItem]) -> StaleArtifactTotals {
        StaleArtifactTotals(bytes: items.reduce(0) { $0 + $1.sizeBytes }, count: items.count)
    }

    // MARK: - Measuring

    /// Sizes the found artifacts with bounded concurrency, as the standalone
    /// app's watch check did; measurements cut short by cancellation are
    /// dropped, so an unmeasured item never counts as idle.
    private static func measure(_ items: [CleanableItem], width: Int) async -> [CleanableItem] {
        await withTaskGroup(of: (String, DirectorySizer.Measurement).self) { group in
            var iterator = items.makeIterator()
            func addNext() {
                guard let item = iterator.next() else { return }
                group.addTask {
                    (item.id, DirectorySizer.measure(item.url))
                }
            }
            for _ in 0..<max(1, width) { addNext() }
            var measurements: [String: DirectorySizer.Measurement] = [:]
            for await (id, measurement) in group {
                if Task.isCancelled { break }
                if measurement.isComplete { measurements[id] = measurement }
                addNext()
            }
            return items.map { item in
                guard let measurement = measurements[item.id] else { return item }
                var measured = item
                measured.sizeBytes = measurement.bytes
                measured.isMeasured = true
                measured.lastModified = measurement.newestModification
                return measured
            }
        }
    }

    private static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoPermissionError { return true }
        let underlying = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError) ?? nsError
        return underlying.domain == NSPOSIXErrorDomain
            && (underlying.code == Int(EACCES) || underlying.code == Int(EPERM))
    }
}
