import Darwin
import Foundation

/// An explicit repair action only. Never escalates privilege or signals a
/// process selected solely by a stale PID or a shared helper name.
@MainActor
struct SystemProcessForceTerminator: ProcessForceTerminating {
    struct Identity {
        let userIdentifier: uid_t
        let executablePath: String
        let startTime: ProcessStartTime
    }

    private let readIdentity: @MainActor (Int32) throws -> Identity?
    private let sendKill: @MainActor (Int32) -> Int32

    init(readIdentity: @escaping @MainActor (Int32) throws -> Identity? = Self.readIdentity,
         sendKill: @escaping @MainActor (Int32) -> Int32 = { Darwin.kill($0, SIGKILL) }) {
        self.readIdentity = readIdentity
        self.sendKill = sendKill
    }

    func forceTerminate(_ process: AffectedProcess) throws {
        guard process.processIdentifier > 1,
              process.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw ProcessTerminationError.protectedProcess
        }
        guard process.canForceTerminate, let startTime = process.startTime else {
            throw ProcessTerminationError.unreadableIdentity
        }
        guard let current = try readIdentity(process.processIdentifier) else {
            throw ProcessTerminationError.identityChanged
        }
        guard current.userIdentifier == geteuid() else {
            throw ProcessTerminationError.protectedProcess
        }
        guard current.startTime == startTime,
              current.executablePath == process.executablePath else {
            throw ProcessTerminationError.identityChanged
        }
        // macOS has no pidfd-style atomic signal operation. Keep identity
        // validation adjacent to the signal; the kernel still enforces UID.
        errno = 0
        guard sendKill(process.processIdentifier) == 0 else {
            throw ProcessTerminationError.signalFailed(errno)
        }
    }

    /// Shared with normal quit requests so both actions reject PID reuse.
    static func readIdentity(_ processIdentifier: Int32) throws -> Identity? {
        var path = [CChar](repeating: 0, count: 4_096)
        errno = 0
        guard proc_pidpath(processIdentifier, &path, UInt32(path.count)) > 0 else {
            if errno == ESRCH { return nil }
            throw ProcessTerminationError.unreadableIdentity
        }
        let executablePath = URL(fileURLWithPath: String(cString: path))
            .standardizedFileURL.resolvingSymlinksInPath().path
        // Read birth time last so exit/PID reuse during path resolution cannot
        // pair the old process's birth time with a replacement's executable.
        var information = proc_bsdinfo()
        let expected = Int32(MemoryLayout<proc_bsdinfo>.size)
        errno = 0
        let size = proc_pidinfo(processIdentifier, PROC_PIDTBSDINFO, 0, &information, expected)
        guard size == expected else {
            if size == 0, errno == ESRCH { return nil }
            throw ProcessTerminationError.unreadableIdentity
        }
        return Identity(userIdentifier: information.pbi_uid,
                        executablePath: executablePath,
                        startTime: ProcessStartTime(seconds: Int64(information.pbi_start_tvsec),
                                                    microseconds: Int64(information.pbi_start_tvusec)))
    }
}
