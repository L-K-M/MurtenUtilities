import AppKit
import DoctorCore
import Security

/// Finds out what each permission client is on this Mac. Tests replace it.
protocol ClientResolving: Sendable {
    func resolve(_ records: [PermissionRecord]) async -> [ResolvedRecord]
}

/// LaunchServices for bundle identifiers, the file system for paths, and
/// Security.framework for whether an app still satisfies the code
/// requirement recorded with its decision. It reads app bundles and never
/// launches, changes or prompts for anything; with the Full Disk Access the
/// database read needed, reading apps in guarded folders raises no prompt.
struct ClientResolver: ClientResolving {
    let home: String

    init(home: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.home = home
    }

    func resolve(_ records: [PermissionRecord]) async -> [ResolvedRecord] {
        var clients: [String: Resolution] = [:]
        var result: [ResolvedRecord] = []
        result.reserveCapacity(records.count)
        for record in records {
            if Task.isCancelled { break }
            let key = Self.key(record.client, record.clientKind)
            let client = clients[key] ?? resolution(of: record.client, kind: record.clientKind)
            clients[key] = client

            var target: ClientStatus?
            if let identifier = record.target {
                let kind: PermissionRecord.ClientKind = identifier.hasPrefix("/") ? .path : .bundleIdentifier
                let targetKey = Self.key(identifier, kind)
                let resolved = clients[targetKey] ?? resolution(of: identifier, kind: kind)
                clients[targetKey] = resolved
                target = resolved.status
            }
            result.append(ResolvedRecord(record: record, client: client.status,
                                         signature: signature(record, client: client), target: target))
        }
        return result
    }

    /// A client's status and every copy of it on a connected disk, the
    /// ones outside the Trash first.
    private struct Resolution {
        let status: ClientStatus
        let copies: [String]
    }

    private static func key(_ identifier: String, _ kind: PermissionRecord.ClientKind) -> String {
        (kind == .path ? "path:" : "bundle:") + identifier
    }

    // MARK: - Clients

    private func resolution(of identifier: String, kind: PermissionRecord.ClientKind) -> Resolution {
        let exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
        switch kind {
        case .bundleIdentifier:
            // Every copy LaunchServices knows, symlinks resolved so Safari's
            // cryptex copy reads as the system's.
            let paths = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: identifier)
                .map { $0.resolvingSymlinksInPath().path }
            let presence = ClientStatus.presence(of: paths, home: home, exists: exists)
            let name = presence.path.flatMap(Self.appName) ?? identifier
            let status = ClientStatus(name: name, presence: presence,
                                      isSystem: ClientStatus.isSystem(client: identifier, kind: kind, presence: presence),
                                      appIdentifier: identifier)
            let present = paths.filter(exists)
            let copies = present.filter { !ClientStatus.isInTrash($0, home: home) } + present.filter { ClientStatus.isInTrash($0, home: home) }
            return Resolution(status: status, copies: copies)
        case .path:
            let presence = ClientStatus.presence(of: [identifier], home: home, exists: exists)
            let app = ClientStatus.enclosingAppPath(of: identifier)
            let info = app.flatMap(Self.info)
            let name = app.flatMap(Self.appName) ?? (identifier as NSString).lastPathComponent
            let status = ClientStatus(name: name.isEmpty ? identifier : name, presence: presence,
                                      isSystem: ClientStatus.isSystem(client: identifier, kind: kind, presence: presence),
                                      appIdentifier: info?["CFBundleIdentifier"] as? String)
            return Resolution(status: status, copies: exists(identifier) ? [identifier] : [])
        }
    }

    private static func info(_ appPath: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Info.plist")) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    private static func appName(_ appPath: String) -> String? {
        let info = info(appPath)
        let name = (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String)
        if let name, !name.isEmpty { return name }
        guard appPath.hasSuffix(".app") else { return nil }
        return URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
    }

    // MARK: - Code requirement

    /// Checks each copy of the client against the record's requirement,
    /// without hashing every resource: the question is whether this is
    /// still the code the decision was made for, not whether the bundle is
    /// intact. One satisfying copy is enough, since macOS honours the
    /// decision for that copy; it is changed only when every copy checked
    /// fails the requirement.
    private func signature(_ record: PermissionRecord, client: Resolution) -> SignatureCheck {
        guard let requirementData = record.requirement else {
            return .notChecked("No code requirement was recorded with this decision.")
        }
        switch client.status.presence {
        case .installed, .inTrash: break
        case .offline: return .notChecked("The app is on a disk that is not connected.")
        case .missing: return .notChecked("The app is not on this Mac.")
        }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithData(requirementData as CFData, [], &requirement) == errSecSuccess, let requirement else {
            return .notChecked("The recorded code requirement could not be read.")
        }
        var failedCopies = 0
        var lastProblem = "No copy of the app could be checked."
        for path in client.copies {
            switch Self.check(path, against: requirement) {
            case .success: return .matches
            case .failure(.mismatch): failedCopies += 1
            case .failure(.unchecked(let problem)): lastProblem = problem
            }
        }
        return failedCopies > 0 && failedCopies == client.copies.count ? .changed : .notChecked(lastProblem)
    }

    private enum CheckProblem: Error {
        case mismatch
        case unchecked(String)
    }

    private static func check(_ path: String, against requirement: SecRequirement) -> Result<Void, CheckProblem> {
        var code: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code)
        guard created == errSecSuccess, let code else {
            return .failure(.unchecked("The app's code could not be opened (OSStatus \(created))."))
        }
        let flags = SecCSFlags(rawValue: kSecCSDoNotValidateResources | kSecCSDoNotValidateExecutable)
        switch SecStaticCodeCheckValidity(code, flags, requirement) {
        case errSecSuccess: return .success(())
        case errSecCSReqFailed, errSecCSUnsigned: return .failure(.mismatch)
        case let status: return .failure(.unchecked("The signature check did not finish (OSStatus \(status))."))
        }
    }
}
