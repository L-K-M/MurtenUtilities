import Foundation

/// The outcome of reading one privacy database. Every way it can fail is
/// named, so an unreadable database is never shown as an empty one.
public enum DatabaseReading: Sendable {
    case read([PermissionRecord])
    /// No database at its path. macOS 27 keeps the per-user one out of reach.
    case missing
    /// macOS refused to open it: the suite has no Full Disk Access.
    case needsFullDiskAccess
    case failed(String)

    public var records: [PermissionRecord] {
        if case .read(let records) = self { return records }
        return []
    }

    /// Maps the `errno` of a failed `stat` or open. `EPERM` is the privacy
    /// system refusing; `EACCES` is ordinary file permissions, which Full
    /// Disk Access would not change.
    public static func forOpenFailure(errno code: Int32, detail: String) -> DatabaseReading {
        switch code {
        case ENOENT, ENOTDIR: return .missing
        case EPERM: return .needsFullDiskAccess
        default: return .failed(detail)
        }
    }
}

/// One database and what reading it gave.
public struct DatabaseSource: Sendable {
    public let database: PermissionRecord.Database
    public let reading: DatabaseReading

    public init(database: PermissionRecord.Database, reading: DatabaseReading) {
        self.database = database
        self.reading = reading
    }

    /// The source's state in a sentence, for the pane and the report.
    public var summary: String {
        switch reading {
        case .read(let records):
            return "\(database.title): read, \(records.count) \(records.count == 1 ? "entry" : "entries")."
        case .missing:
            return database == .user
                ? "\(database.title): not readable on this version of macOS. Check these lists in System Settings."
                : "\(database.title): no database found."
        case .needsFullDiskAccess:
            return "\(database.title): needs Full Disk Access."
        case .failed(let detail):
            return "\(database.title): could not be read. \(detail)"
        }
    }
}
