import AppKit
import Darwin
import DoctorCore
import Foundation
import Security

struct ProcessIdentity: Equatable, Sendable {
    let processIdentifier: Int32
    let executablePath: String
    let signingIdentifier: String?
    let enclosingAppIdentifier: String?
    let responsibleProcessIdentifier: Int32
    let signingIdentityAvailable: Bool
    let userIdentifier: uid_t

    init(processIdentifier: Int32, executablePath: String, signingIdentifier: String?,
         enclosingAppIdentifier: String? = nil,
         responsibleProcessIdentifier: Int32? = nil,
         signingIdentityAvailable: Bool = true,
         userIdentifier: uid_t = getuid()) {
        self.processIdentifier = processIdentifier
        self.executablePath = executablePath
        self.signingIdentifier = signingIdentifier
        self.enclosingAppIdentifier = enclosingAppIdentifier
        self.responsibleProcessIdentifier = responsibleProcessIdentifier ?? processIdentifier
        self.signingIdentityAvailable = signingIdentityAvailable
        self.userIdentifier = userIdentifier
    }
}

protocol ProcessInventoryReading: Sendable {
    func snapshot() async throws -> [ProcessIdentity]
}

/// Reads every PID through libproc, then obtains the executable's signing
/// identifier through Security.framework. Unlike `NSWorkspace`, this also
/// covers helpers, agents, command-line tools, and background-only apps.
struct SystemProcessInventory: ProcessInventoryReading {
    private typealias ResponsibleFunction = @convention(c) (pid_t) -> pid_t
    private static let responsibleFunction: ResponsibleFunction? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: ResponsibleFunction.self)
    }()

    func snapshot() async throws -> [ProcessIdentity] {
        try await Task.detached(priority: .userInitiated) {
            try Self.readSnapshot()
        }.value
    }

    private static func readSnapshot() throws -> [ProcessIdentity] {
        var pending = Set(try allProcessIdentifiers())
        var seen = Set<Int32>()
        var inspected: [Int32: ProcessIdentity] = [:]

        // Signing inspection takes long enough for another process to launch.
        // Fold newly observed PIDs into the same snapshot until an enumeration
        // adds nothing; persistent churn is an explicit fail-closed result.
        for _ in 0..<32 {
            seen.formUnion(pending)
            for processIdentifier in pending {
                try Task.checkCancellation()
                guard let executablePath = try executablePath(for: processIdentifier) else {
                    continue // The process exited between enumeration and inspection.
                }
                guard let userIdentifier = try userIdentifier(for: processIdentifier) else {
                    continue
                }
                guard let responsibleProcessIdentifier = try responsibleProcessIdentifier(
                    for: processIdentifier, userIdentifier: userIdentifier
                ) else {
                    continue // It exited after its path was read.
                }
                let signingIdentity = signingIdentity(for: processIdentifier,
                                                      executablePath: executablePath)
                inspected[processIdentifier] = ProcessIdentity(
                    processIdentifier: processIdentifier,
                    executablePath: executablePath,
                    signingIdentifier: signingIdentity.identifier,
                    enclosingAppIdentifier: enclosingAppIdentifier(for: executablePath),
                    responsibleProcessIdentifier: responsibleProcessIdentifier,
                    signingIdentityAvailable: signingIdentity.available,
                    userIdentifier: userIdentifier
                )
            }
            let latest = Set(try allProcessIdentifiers())
            pending = latest.subtracting(seen)
            if pending.isEmpty { return Array(inspected.values) }
        }
        throw LifecycleError.processInventoryUnstable
    }

    private static func allProcessIdentifiers() throws -> [Int32] {
        var capacity = 2_048
        while capacity <= 131_072 {
            var processIdentifiers = [pid_t](repeating: 0, count: capacity)
            let count = proc_listallpids(&processIdentifiers,
                                         Int32(processIdentifiers.count * MemoryLayout<pid_t>.size))
            guard count >= 0 else {
                throw LifecycleError.processInventoryUnavailable(errno)
            }
            guard count < capacity else {
                capacity *= 2
                continue
            }
            return Array(processIdentifiers[0..<Int(count)]).filter { $0 > 0 }.map { Int32($0) }
        }
        throw LifecycleError.processInventoryTruncated
    }

    private static func executablePath(for processIdentifier: Int32) throws -> String? {
        var buffer = [CChar](repeating: 0, count: 4_096)
        errno = 0
        let length = proc_pidpath(processIdentifier, &buffer, UInt32(buffer.count))
        if length > 0 {
            return String(cString: buffer)
        }
        let pathError = errno
        let processConfirmedAbsent = pathError == ENOENT
            && isProcessConfirmedAbsent(processIdentifier)
        try validateExecutablePathFailure(
            errorNumber: pathError,
            processIdentifier: processIdentifier,
            processConfirmedAbsent: processConfirmedAbsent
        )
        return nil
    }

    static func validateExecutablePathFailure(errorNumber: Int32,
                                              processIdentifier: Int32,
                                              processConfirmedAbsent: Bool) throws {
        if errorNumber == ESRCH { return }
        if errorNumber == ENOENT, processConfirmedAbsent { return }
        throw LifecycleError.processPathUnavailable(processIdentifier, errorNumber)
    }

    private static func isProcessConfirmedAbsent(_ processIdentifier: Int32) -> Bool {
        errno = 0
        return kill(processIdentifier, 0) < 0 && errno == ESRCH
    }

    private static func userIdentifier(for processIdentifier: Int32) throws -> uid_t? {
        var query: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, processIdentifier]
        let queryCount = UInt32(query.count)
        var information = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        errno = 0
        let status = query.withUnsafeMutableBufferPointer {
            sysctl($0.baseAddress, queryCount, &information, &size, nil, 0)
        }
        return try interpretUserIdentifierQuery(
            status: status,
            returnedSize: size,
            expectedSize: MemoryLayout<kinfo_proc>.size,
            userIdentifier: information.kp_eproc.e_ucred.cr_uid,
            errorNumber: errno,
            processIdentifier: processIdentifier
        )
    }

    static func interpretUserIdentifierQuery(status: Int32, returnedSize: Int,
                                             expectedSize: Int, userIdentifier: uid_t,
                                             errorNumber: Int32,
                                             processIdentifier: Int32) throws -> uid_t? {
        if status == 0, returnedSize == expectedSize { return userIdentifier }
        // KERN_PROC_PID reports a successful zero-length result when the PID
        // exits between enumeration and inspection.
        if status == 0, returnedSize == 0 { return nil }
        if errorNumber == ESRCH { return nil }
        throw LifecycleError.processIdentityReadFailed(processIdentifier, errorNumber)
    }

    private static func responsibleProcessIdentifier(for processIdentifier: Int32,
                                                     userIdentifier: uid_t) throws -> Int32? {
        guard let responsibleFunction else {
            throw LifecycleError.responsibilityUnavailable
        }
        errno = 0
        let responsible = responsibleFunction(processIdentifier)
        if responsible >= 0 { return responsible }
        if errno == ESRCH { return nil }
        // Another user's private responsibility chain may be inaccessible.
        // Preserve the process so its own identity is still inspected and
        // matched instead of dropping a possibly affected app.
        if (errno == EPERM || errno == EACCES), userIdentifier != getuid() {
            return processIdentifier
        }
        throw LifecycleError.responsibilityReadFailed(processIdentifier, errno)
    }

    private static func signingIdentity(for processIdentifier: Int32,
                                        executablePath: String) -> (identifier: String?, available: Bool) {
        var dynamicCode: SecCode?
        let attributes = [kSecGuestAttributePid as String: processIdentifier] as CFDictionary
        if SecCodeCopyGuestWithAttributes(nil, attributes, [], &dynamicCode) == errSecSuccess,
           let dynamicCode {
            var staticCode: SecStaticCode?
            if SecCodeCopyStaticCode(dynamicCode, [], &staticCode) == errSecSuccess,
               let staticCode,
               let identifier = signingIdentifier(for: staticCode) {
                return (identifier, true)
            }
        }

        var code: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(URL(fileURLWithPath: executablePath) as CFURL, [], &code)
        guard createStatus == errSecSuccess, let code else {
            return (nil, createStatus == errSecCSUnsigned)
        }
        var information: CFDictionary?
        let informationStatus = SecCodeCopySigningInformation(
            code, SecCSFlags(rawValue: kSecCSSigningInformation), &information
        )
        if informationStatus == errSecCSUnsigned { return (nil, true) }
        guard informationStatus == errSecSuccess,
              let details = information as? [String: Any] else { return (nil, false) }
        return (details[kSecCodeInfoIdentifier as String] as? String, true)
    }

    private static func signingIdentifier(for code: SecStaticCode) -> String? {
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let details = information as? [String: Any] else { return nil }
        return details[kSecCodeInfoIdentifier as String] as? String
    }

    private static func enclosingAppIdentifier(for executablePath: String) -> String? {
        let components = URL(fileURLWithPath: executablePath).pathComponents
        guard let appIndex = components.indices.first(where: {
            components[$0].lowercased().hasSuffix(".app")
        }) else { return nil }
        let appPath = NSString.path(withComponents: Array(components[...appIndex]))
        return Bundle(url: URL(fileURLWithPath: appPath))?.bundleIdentifier
    }
}

@MainActor
final class WorkspaceApplicationLifecycle: ApplicationLifecycleManaging {
    private struct ProcessKey: Hashable {
        let processIdentifier: Int32
        let executablePath: String
    }

    private let inventory: any ProcessInventoryReading
    /// Once a helper has been attributed to an affected app, keep recognizing
    /// the same live PID/path even after its responsible main app exits.
    private var implicatedProcesses = Set<ProcessKey>()

    init(inventory: any ProcessInventoryReading = SystemProcessInventory()) {
        self.inventory = inventory
    }

    func runningProcesses(matching clients: Set<String>) async throws -> [AffectedProcess] {
        let bundleIdentifiers = clients.filter(ClientIdentifier.isBundleIdentifier)
        let pathClients = Set(clients.filter { $0.hasPrefix("/") }.map(Self.normalizedPath))
        var matches: [Int32: AffectedProcess] = [:]
        let snapshot = try await inventory.snapshot()
        let byProcessIdentifier = Dictionary(snapshot.map { ($0.processIdentifier, $0) }) { first, _ in first }
        let liveKeys = Set(snapshot.map {
            ProcessKey(processIdentifier: $0.processIdentifier,
                       executablePath: Self.normalizedPath($0.executablePath))
        })
        implicatedProcesses.formIntersection(liveKeys)

        for process in snapshot {
            let executablePath = Self.normalizedPath(process.executablePath)
            let running = NSRunningApplication(processIdentifier: process.processIdentifier)
            if !bundleIdentifiers.isEmpty, !process.signingIdentityAvailable {
                throw LifecycleError.processIdentityUnavailable(process.processIdentifier)
            }

            var attributedIdentifiers = Set([
                process.signingIdentifier,
                process.enclosingAppIdentifier,
                running?.bundleIdentifier
            ].compactMap { $0 })
            var responsible = process.responsibleProcessIdentifier
            var visited = Set<Int32>()
            if responsible != process.processIdentifier,
               byProcessIdentifier[responsible] == nil,
               process.userIdentifier == getuid(),
               !implicatedProcesses.contains(keyFor(process)) {
                throw LifecycleError.responsibleProcessMissing(process.processIdentifier,
                                                               responsible)
            }
            while responsible != process.processIdentifier,
                  visited.insert(responsible).inserted,
                  let owner = byProcessIdentifier[responsible] {
                attributedIdentifiers.formUnion([
                    owner.signingIdentifier,
                    owner.enclosingAppIdentifier
                ].compactMap { $0 })
                if owner.responsibleProcessIdentifier == responsible { break }
                responsible = owner.responsibleProcessIdentifier
            }

            let key = ProcessKey(processIdentifier: process.processIdentifier,
                                 executablePath: executablePath)
            let directlyMatches = pathClients.contains(executablePath)
                || !attributedIdentifiers.isDisjoint(with: bundleIdentifiers)
            if directlyMatches { implicatedProcesses.insert(key) }
            guard directlyMatches || implicatedProcesses.contains(key) else { continue }

            matches[process.processIdentifier] = AffectedProcess(
                processIdentifier: process.processIdentifier,
                name: running?.localizedName ?? URL(fileURLWithPath: executablePath).lastPathComponent,
                executablePath: executablePath,
                canRequestTermination: running != nil
                    && process.processIdentifier != ProcessInfo.processInfo.processIdentifier
            )
        }
        return Self.sorted(matches.values)
    }

    func requestTermination(of processes: [AffectedProcess]) {
        for process in processes where process.canRequestTermination {
            guard process.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let application = NSRunningApplication(processIdentifier: process.processIdentifier),
                  let currentPath = application.executableURL?.path,
                  Self.normalizedPath(currentPath) == process.executablePath else { continue }
            _ = application.terminate()
        }
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func keyFor(_ process: ProcessIdentity) -> ProcessKey {
        ProcessKey(processIdentifier: process.processIdentifier,
                   executablePath: Self.normalizedPath(process.executablePath))
    }

    private static func sorted<S: Sequence>(_ processes: S) -> [AffectedProcess] where S.Element == AffectedProcess {
        processes.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.processIdentifier < $1.processIdentifier : order == .orderedAscending
        }
    }
}

enum LifecycleError: LocalizedError {
    case processInventoryUnavailable(Int32)
    case processInventoryTruncated
    case processInventoryUnstable
    case processPathUnavailable(Int32, Int32)
    case processIdentityReadFailed(Int32, Int32)
    case processIdentityUnavailable(Int32)
    case responsibilityUnavailable
    case responsibilityReadFailed(Int32, Int32)
    case responsibleProcessMissing(Int32, Int32)

    var errorDescription: String? {
        switch self {
        case .processInventoryUnavailable(let code):
            return "The running-process list could not be read (error \(code)). No further permissions were reset."
        case .processInventoryTruncated:
            return "The running-process list changed too quickly to inspect completely. No further permissions were reset."
        case .processInventoryUnstable:
            return "New processes kept appearing during the safety check. No further permissions were reset."
        case .processPathUnavailable(let processIdentifier, let code):
            return "Process \(processIdentifier) could not be identified safely (error \(code)). No further permissions were reset."
        case .processIdentityReadFailed(let processIdentifier, let code):
            return "Process \(processIdentifier)'s owner could not be identified (error \(code)). No further permissions were reset."
        case .processIdentityUnavailable(let processIdentifier):
            return "Process \(processIdentifier)'s signing identity could not be inspected. No further permissions were reset."
        case .responsibilityUnavailable:
            return "macOS did not provide process-responsibility information. No further permissions were reset."
        case .responsibilityReadFailed(let processIdentifier, let code):
            return "Process \(processIdentifier)'s responsible app could not be identified (error \(code)). No further permissions were reset."
        case .responsibleProcessMissing(let processIdentifier, let responsibleProcessIdentifier):
            return "Process \(processIdentifier)'s responsible app (process \(responsibleProcessIdentifier)) is no longer available to inspect. No further permissions were reset."
        }
    }
}
