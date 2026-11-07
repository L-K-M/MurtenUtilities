import AppKit
import Darwin
import DoctorCore
import Foundation
import Security

/// The process whose identity TCC attributes another process's requests to.
enum ProcessResponsibility: Equatable, Sendable {
    /// The responsible process macOS reported: the process itself for most
    /// apps and daemons, or the app a helper or XPC service works for.
    case process(Int32)
    /// macOS refuses responsibility lookups to an unprivileged caller for
    /// every process another user owns: launchd, WindowServer, tccd and the
    /// other system daemons, role accounts, and other login sessions. Such a
    /// process is attributed by its own identity and its live parent chain.
    case unreadable(parentProcessIdentifier: Int32)
}

struct ProcessIdentity: Equatable, Sendable {
    let processIdentifier: Int32
    let executablePath: String
    let signingIdentifier: String?
    let enclosingAppIdentifier: String?
    let responsibility: ProcessResponsibility
    let signingIdentityAvailable: Bool
    let userIdentifier: uid_t
    let startTime: ProcessStartTime?

    init(processIdentifier: Int32, executablePath: String, signingIdentifier: String?,
         enclosingAppIdentifier: String? = nil,
         responsibility: ProcessResponsibility? = nil,
         signingIdentityAvailable: Bool = true,
         userIdentifier: uid_t = getuid(), startTime: ProcessStartTime? = nil) {
        self.processIdentifier = processIdentifier
        self.executablePath = executablePath
        self.signingIdentifier = signingIdentifier
        self.enclosingAppIdentifier = enclosingAppIdentifier
        self.responsibility = responsibility ?? .process(processIdentifier)
        self.signingIdentityAvailable = signingIdentityAvailable
        self.userIdentifier = userIdentifier
        self.startTime = startTime
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

    private typealias CodeSigningOperation = @convention(c) (pid_t, UInt32, UnsafeMutableRawPointer?, Int) -> Int32
    private static let codeSigningOperation: CodeSigningOperation? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "csops") else {
            return nil
        }
        return unsafeBitCast(symbol, to: CodeSigningOperation.self)
    }()
    /// `CS_OPS_IDENTITY` in xnu's <sys/codesign.h>, which the SDK omits.
    private static let codeSigningIdentityOperation: UInt32 = 11
    /// The blob `CS_OPS_IDENTITY` returns: a 4-byte magic and a 4-byte
    /// big-endian total length, then the NUL-terminated identifier.
    private static let kernelIdentityHeaderSize = 8

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
                guard let ownership = try ownership(of: processIdentifier) else {
                    continue
                }
                guard let responsibility = try responsibility(of: processIdentifier,
                                                              ownership: ownership) else {
                    continue // It exited after its path was read.
                }
                let signingIdentity = signingIdentity(for: processIdentifier,
                                                      executablePath: executablePath)
                inspected[processIdentifier] = ProcessIdentity(
                    processIdentifier: processIdentifier,
                    executablePath: executablePath,
                    signingIdentifier: signingIdentity.identifier,
                    enclosingAppIdentifier: enclosingAppIdentifier(for: executablePath),
                    responsibility: responsibility,
                    signingIdentityAvailable: signingIdentity.available,
                    userIdentifier: ownership.userIdentifier,
                    startTime: ownership.startTime
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

    private struct Ownership {
        let userIdentifier: uid_t
        let parentProcessIdentifier: Int32
        let startTime: ProcessStartTime
    }

    /// `KERN_PROC_PID` answers for every process, including other users'.
    private static func ownership(of processIdentifier: Int32) throws -> Ownership? {
        var query: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, processIdentifier]
        let queryCount = UInt32(query.count)
        var information = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        errno = 0
        let status = query.withUnsafeMutableBufferPointer {
            sysctl($0.baseAddress, queryCount, &information, &size, nil, 0)
        }
        guard let userIdentifier = try interpretUserIdentifierQuery(
            status: status,
            returnedSize: size,
            expectedSize: MemoryLayout<kinfo_proc>.size,
            userIdentifier: information.kp_eproc.e_ucred.cr_uid,
            errorNumber: errno,
            processIdentifier: processIdentifier
        ) else { return nil }
        return Ownership(userIdentifier: userIdentifier,
                         parentProcessIdentifier: information.kp_eproc.e_ppid,
                         startTime: ProcessStartTime(seconds: Int64(information.kp_proc.p_starttime.tv_sec),
                                                     microseconds: Int64(information.kp_proc.p_starttime.tv_usec)))
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

    private static func responsibility(of processIdentifier: Int32,
                                       ownership: Ownership) throws -> ProcessResponsibility? {
        guard let responsibleFunction else {
            throw LifecycleError.responsibilityUnavailable
        }
        errno = 0
        let responsible = responsibleFunction(processIdentifier)
        return try interpretResponsibilityResult(
            responsible: responsible,
            errorNumber: errno,
            processIdentifier: processIdentifier,
            processUserIdentifier: ownership.userIdentifier,
            callerUserIdentifier: geteuid(),
            parentProcessIdentifier: ownership.parentProcessIdentifier
        )
    }

    static func interpretResponsibilityResult(responsible: Int32, errorNumber: Int32,
                                               processIdentifier: Int32,
                                               processUserIdentifier: uid_t,
                                               callerUserIdentifier: uid_t,
                                               parentProcessIdentifier: Int32) throws -> ProcessResponsibility? {
        if responsible >= 0 { return .process(responsible) }
        if errorNumber == ESRCH { return nil }
        // Without root, macOS denies this lookup for every process another
        // user owns, so a normal Mac always has hundreds of them (launchd,
        // WindowServer, tccd). Failing on those would make Reset All
        // unusable; attribute them by identity and parent chain instead.
        if errorNumber == EPERM, processUserIdentifier != callerUserIdentifier {
            return .unreadable(parentProcessIdentifier: parentProcessIdentifier)
        }
        // Any other failure, including a denied lookup for one of the
        // user's own processes, cannot prove that a helper is unrelated to
        // an affected app.
        throw LifecycleError.responsibilityReadFailed(processIdentifier, errorNumber)
    }

    private static func signingIdentity(for processIdentifier: Int32,
                                        executablePath: String) -> (identifier: String?, available: Bool) {
        let fromSignature = codeSignatureIdentity(for: processIdentifier, executablePath: executablePath)
        if fromSignature.available { return fromSignature }

        // Security.framework reads the executable, which another user's
        // process may keep unreadable: roleaccountd stages root XPC
        // services (Xcode's Instruments helpers) in a root-only directory.
        // The kernel still knows the identifier the running code was
        // signed with, and reports it without privilege.
        if let identifier = kernelSigningIdentifier(for: processIdentifier) {
            return (identifier, true)
        }
        return fromSignature
    }

    private static func kernelSigningIdentifier(for processIdentifier: Int32) -> String? {
        guard let codeSigningOperation else { return nil }
        var blob = [UInt8](repeating: 0, count: 1_024)
        let status = blob.withUnsafeMutableBytes {
            codeSigningOperation(processIdentifier, codeSigningIdentityOperation,
                                 $0.baseAddress, $0.count)
        }
        return interpretKernelIdentity(status: status, blob: blob)
    }

    /// Any malformed, truncated or empty answer yields nil, which keeps the
    /// process's identity unavailable so Reset All fails closed.
    static func interpretKernelIdentity(status: Int32, blob: [UInt8]) -> String? {
        let headerSize = kernelIdentityHeaderSize
        guard status == 0, blob.count > headerSize else { return nil }
        let declaredLength = blob[4..<headerSize].reduce(0) { $0 << 8 | Int($1) }
        guard declaredLength > headerSize, declaredLength <= blob.count else { return nil }
        let identifier = blob[headerSize..<declaredLength].prefix { $0 != 0 }
        guard !identifier.isEmpty else { return nil }
        return String(bytes: identifier, encoding: .utf8)
    }

    private static func codeSignatureIdentity(for processIdentifier: Int32,
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
        let startTime: ProcessStartTime?
    }

    private let inventory: any ProcessInventoryReading
    private let forceTerminator: any ProcessForceTerminating
    /// Once a helper has been attributed to an affected app, keep recognizing
    /// the same live process even after its responsible main app exits. Birth
    /// time prevents a replacement PID from inheriting the old attribution.
    private var implicatedProcesses = Set<ProcessKey>()

    init(inventory: any ProcessInventoryReading = SystemProcessInventory(),
         forceTerminator: (any ProcessForceTerminating)? = nil) {
        self.inventory = inventory
        self.forceTerminator = forceTerminator ?? SystemProcessForceTerminator()
    }

    func runningProcesses(matching clients: Set<String>) async throws -> [AffectedProcess] {
        let bundleIdentifiers = clients.filter(ClientIdentifier.isBundleIdentifier)
        let pathClients = Set(clients.filter { $0.hasPrefix("/") }.map(Self.normalizedPath))
        var matches: [Int32: AffectedProcess] = [:]
        let snapshot = try await inventory.snapshot()
        let byProcessIdentifier = Dictionary(snapshot.map { ($0.processIdentifier, $0) }) { first, _ in first }
        let liveKeys = Set(snapshot.map {
            ProcessKey(processIdentifier: $0.processIdentifier,
                       executablePath: Self.normalizedPath($0.executablePath), startTime: $0.startTime)
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
            var attributedProcess = process
            var visited = Set<Int32>()
            while let link = Self.attributionLink(of: attributedProcess) {
                guard visited.insert(attributedProcess.processIdentifier).inserted,
                      !visited.contains(link.processIdentifier) else {
                    throw LifecycleError.responsibilityCycle(process.processIdentifier)
                }
                guard let owner = byProcessIdentifier[link.processIdentifier] else {
                    // macOS reparents an orphan to launchd, so a parent that
                    // exited mid-snapshot ends the chain exactly as the next
                    // snapshot would; failing here would only abort a reset.
                    if case .parent = link { break }
                    // An already-attributed helper must stay affected after
                    // its main app exits. Otherwise the missing owner leaves
                    // the process's relationship to affected apps unknown;
                    // unlike a parent, a stale responsible PID persists.
                    if implicatedProcesses.contains(keyFor(process)) { break }
                    throw LifecycleError.responsibleProcessMissing(process.processIdentifier,
                                                                   link.processIdentifier)
                }
                attributedIdentifiers.formUnion([
                    owner.signingIdentifier,
                    owner.enclosingAppIdentifier
                ].compactMap { $0 })
                attributedProcess = owner
            }

            let key = ProcessKey(processIdentifier: process.processIdentifier,
                                 executablePath: executablePath, startTime: process.startTime)
            let directlyMatches = pathClients.contains(executablePath)
                || !attributedIdentifiers.isDisjoint(with: bundleIdentifiers)
            if directlyMatches { implicatedProcesses.insert(key) }
            guard directlyMatches || implicatedProcesses.contains(key) else { continue }

            matches[process.processIdentifier] = AffectedProcess(
                processIdentifier: process.processIdentifier,
                name: running?.localizedName ?? URL(fileURLWithPath: executablePath).lastPathComponent,
                executablePath: executablePath,
                canRequestTermination: running != nil
                    && process.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                startTime: process.startTime,
                canForceTerminate: process.startTime != nil
                    && process.userIdentifier == geteuid()
                    && process.processIdentifier > 1
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
            if let startTime = process.startTime {
                guard let current = try? SystemProcessForceTerminator.readIdentity(process.processIdentifier),
                      current.startTime == startTime,
                      current.executablePath == process.executablePath else { continue }
            }
            _ = application.terminate()
        }
    }

    func forceTerminate(_ process: AffectedProcess) throws {
        try forceTerminator.forceTerminate(process)
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// The next process whose identity a process's TCC requests may carry.
    private enum AttributionLink {
        case responsible(Int32)
        case parent(Int32)

        var processIdentifier: Int32 {
            switch self {
            case .responsible(let processIdentifier), .parent(let processIdentifier):
                return processIdentifier
            }
        }
    }

    private static let launchdProcessIdentifier: Int32 = 1

    private static func attributionLink(of process: ProcessIdentity) -> AttributionLink? {
        switch process.responsibility {
        case .process(let responsible):
            return responsible == process.processIdentifier ? nil : .responsible(responsible)
        case .unreadable(let parent):
            // A child inherits its parent's responsibility unless it opts
            // out, so following the parent can only add affected apps.
            // launchd sets responsibility for the jobs it starts, so the
            // chain carries nothing past it. Without root, a launchd job
            // working for an app (an XPC service) is matched only by its
            // own identity; its client is matched while it runs.
            return parent > launchdProcessIdentifier ? .parent(parent) : nil
        }
    }

    private func keyFor(_ process: ProcessIdentity) -> ProcessKey {
        ProcessKey(processIdentifier: process.processIdentifier,
                   executablePath: Self.normalizedPath(process.executablePath), startTime: process.startTime)
    }

    private static func sorted<S: Sequence>(_ processes: S) -> [AffectedProcess] where S.Element == AffectedProcess {
        processes.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.processIdentifier < $1.processIdentifier : order == .orderedAscending
        }
    }
}

/// Descriptions state what failed. Callers add what was or was not reset,
/// because the same check runs during inspection and between resets.
enum LifecycleError: LocalizedError {
    case processInventoryUnavailable(Int32)
    case processInventoryTruncated
    case processInventoryUnstable
    case processPathUnavailable(Int32, Int32)
    case processIdentityReadFailed(Int32, Int32)
    case processIdentityUnavailable(Int32)
    case responsibilityUnavailable
    case responsibilityReadFailed(Int32, Int32)
    case responsibilityCycle(Int32)
    case responsibleProcessMissing(Int32, Int32)

    var errorDescription: String? {
        switch self {
        case .processInventoryUnavailable(let code):
            return "The running-process list could not be read (error \(code))."
        case .processInventoryTruncated:
            return "The running-process list changed too quickly to inspect completely."
        case .processInventoryUnstable:
            return "New processes kept appearing during the safety check."
        case .processPathUnavailable(let processIdentifier, let code):
            return "Process \(processIdentifier) could not be identified safely (error \(code))."
        case .processIdentityReadFailed(let processIdentifier, let code):
            return "Process \(processIdentifier)'s owner could not be identified (error \(code))."
        case .processIdentityUnavailable(let processIdentifier):
            return "Process \(processIdentifier)'s signing identity could not be inspected."
        case .responsibilityUnavailable:
            return "macOS did not provide process-responsibility information."
        case .responsibilityReadFailed(let processIdentifier, let code):
            return "Process \(processIdentifier)'s responsible app could not be identified (error \(code))."
        case .responsibilityCycle(let processIdentifier):
            return "Process \(processIdentifier)'s responsibility chain contains a cycle."
        case .responsibleProcessMissing(let processIdentifier, let responsibleProcessIdentifier):
            return "Process \(processIdentifier)'s responsible app (process \(responsibleProcessIdentifier)) is no longer available to inspect."
        }
    }
}
