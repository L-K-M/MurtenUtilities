import Foundation
import BootCaptainCore

/// Reads the launchd property-list folders a standard user can read without a
/// prompt, plus the launchd plists apps embed for `SMAppService`. It parses
/// the same way, and names items the same way, as the pane's
/// `LaunchdFileCollector`, so its identities match the reviewed inventory.
///
/// Left out on purpose: Apple's own folders (`/System/Library`,
/// `/Library/Apple`) and `com.apple.` labels, which change with every OS
/// update; Background Task Management (`sfltool dumpbtm` needs root), login
/// items (System Events needs Automation consent) and other users' homes.
/// Those stay in the pane's on-demand scan.
public struct LaunchdFolderInventory: StartupInventoryObserving {
    public struct Folder: Sendable, Equatable {
        public var path: String
        public var mechanism: Mechanism

        public init(path: String, mechanism: Mechanism) {
            self.path = path
            self.mechanism = mechanism
        }
    }

    public let folders: [Folder]
    /// Folders of `.app` bundles whose `Contents/Library/Launch*` are read.
    public let appFolders: [String]

    public init(folders: [Folder], appFolders: [String]) {
        self.folders = folders
        self.appFolders = appFolders
    }

    /// The live folders for the current user.
    public static func live(home: String = NSHomeDirectory()) -> LaunchdFolderInventory {
        LaunchdFolderInventory(
            folders: [
                Folder(path: "/Library/LaunchDaemons", mechanism: .launchDaemon),
                Folder(path: "/Library/LaunchAgents", mechanism: .launchAgent),
                Folder(path: home + "/Library/LaunchAgents", mechanism: .launchAgent),
            ],
            appFolders: ["/Applications", "/Applications/Setapp", home + "/Applications"])
    }

    static let embeddedFolders: [(subpath: String, mechanism: Mechanism)] = [
        ("Contents/Library/LaunchDaemons", .smAppServiceDaemon),
        ("Contents/Library/LaunchAgents", .smAppServiceAgent),
    ]

    public func observeInventory() async -> StartupInventorySnapshot {
        var reader = Reader()

        for folder in folders {
            guard !Task.isCancelled else { return reader.cancelled(at: folder.path) }
            guard let names = reader.list(folder.path) else { continue }
            for name in names where name.hasSuffix(".plist") {
                reader.readFolderPlist(folder.path + "/" + name, fileName: name, mechanism: folder.mechanism)
            }
        }

        for root in appFolders {
            guard let apps = reader.list(root) else { continue }
            for app in apps.sorted() where app.hasSuffix(".app") {
                guard !Task.isCancelled else { return reader.cancelled(at: root + "/" + app) }
                reader.readApp(root + "/" + app)
            }
        }

        return reader.snapshot
    }

    // MARK: - Reading

    /// One read's state: the snapshot so far and the apps already looked up.
    private struct Reader {
        let fileManager = FileManager.default
        var snapshot = StartupInventorySnapshot()
        var appsByPath: [String: AppIdentity] = [:]

        /// Names in `path`; nil when it is absent (normal) or unreadable
        /// (recorded as a failure, so the check is not complete).
        mutating func list(_ path: String) -> [String]? {
            guard fileManager.fileExists(atPath: path) else { return nil }
            do {
                return try fileManager.contentsOfDirectory(atPath: path)
            } catch {
                snapshot.failures.append(InventoryReadFailure(
                    kind: .unreadable, path: path, reason: error.localizedDescription))
                return nil
            }
        }

        func cancelled(at path: String) -> StartupInventorySnapshot {
            var result = snapshot
            result.failures.append(InventoryReadFailure(kind: .cancelled, path: path,
                                                        reason: "The check was cancelled."))
            return result
        }

        mutating func readFolderPlist(_ path: String, fileName: String, mechanism: Mechanism) {
            // A plist the user cannot read is skipped, exactly as the pane's
            // scan skips it, so neither inventory ever lists it.
            guard let data = fileManager.contents(atPath: path) else { return }

            guard let job = try? LaunchdJobParser.parse(data: data) else {
                // The pane lists an unparsable plist under its file name.
                append(id: "\(mechanism.rawValue):\(fileName)", mechanism: mechanism, label: fileName,
                       path: path, owningApp: nil, associated: [])
                return
            }

            let label = job.label ?? fileName
            let recipe = RecipeResolver.resolve(job)
            let owner = (recipe.trustPath ?? recipe.executablePath).flatMap { owningApp(of: $0) }
            append(id: "\(mechanism.rawValue):\(label)", mechanism: mechanism, label: label, path: path,
                   owningApp: owner, associated: job.associatedBundleIdentifiers)
        }

        mutating func readApp(_ appPath: String) {
            let identity = appIdentity(at: appPath)
            if let bundleID = identity.bundleIdentifier {
                snapshot.installedApps[bundleID] = identity.name
            }

            for embedded in LaunchdFolderInventory.embeddedFolders {
                let directory = appPath + "/" + embedded.subpath
                // As in the pane's scan, an app's own folders are read
                // best-effort; most apps have none.
                guard let names = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
                for name in names where name.hasSuffix(".plist") {
                    let path = directory + "/" + name
                    // The pane skips embedded plists it cannot parse; so does this.
                    guard let data = fileManager.contents(atPath: path),
                          let job = try? LaunchdJobParser.parse(data: data) else { continue }
                    let label = job.label ?? name
                    append(id: "\(embedded.mechanism.rawValue):\(label)", mechanism: embedded.mechanism,
                           label: label, path: path, owningApp: identity,
                           associated: job.associatedBundleIdentifiers)
                }
            }
        }

        private mutating func append(id: String, mechanism: Mechanism, label: String, path: String,
                                     owningApp: AppIdentity?, associated: [String]) {
            guard !label.hasPrefix("com.apple.") else { return }
            snapshot.items.append(WatchedStartupItem(
                id: id, mechanism: mechanism, label: label, sourcePath: path,
                owningApp: owningApp, associatedBundleIdentifiers: associated))
        }

        /// The outermost `.app` containing `path`, as the pane attributes it.
        private mutating func owningApp(of path: String) -> AppIdentity? {
            let components = (path as NSString).pathComponents
            guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
            let appPath = NSString.path(withComponents: Array(components[0...index]))
            return appIdentity(at: appPath)
        }

        private mutating func appIdentity(at appPath: String) -> AppIdentity {
            if let known = appsByPath[appPath] { return known }
            let name = ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension
            var bundleID: String?
            if let data = fileManager.contents(atPath: appPath + "/Contents/Info.plist"),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                bundleID = plist["CFBundleIdentifier"] as? String
            }
            let identity = AppIdentity(name: name, bundleIdentifier: bundleID)
            appsByPath[appPath] = identity
            return identity
        }
    }
}
