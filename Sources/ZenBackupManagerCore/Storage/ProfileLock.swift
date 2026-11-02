import Foundation
import Darwin

/// Firefox/Zen uses a POSIX record lock on .parentlock on macOS. Keep it for
/// the complete transaction, so Zen cannot acquire the profile during a restore.
final class ProfileLock {
    private let descriptor: Int32
    init(directory: URL) throws {
        let path = directory.appendingPathComponent(".parentlock")
        try SessionFiles.validateDestination(path)
        descriptor = open(path.path, O_RDWR | O_CREAT | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw BackupError.invalid("Cannot lock this profile. Check its file permissions.") }
        var lock = flock(l_start: 0, l_len: 0, l_pid: 0, l_type: Int16(F_WRLCK), l_whence: Int16(SEEK_SET))
        guard fcntl(descriptor, F_SETLK, &lock) != -1 else {
            close(descriptor)
            throw BackupError.zenRunning
        }
    }
    deinit { close(descriptor) }
}
