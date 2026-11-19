import Foundation
import DoctorCore
import SQLite3

/// Reads the macOS privacy databases for the inventory. The pane's only
/// reader; tests replace it with fixture readings.
protocol PrivacyDatabaseReading: Sendable {
    func read(_ database: PermissionRecord.Database) -> DatabaseReading
}

/// Opens each database read-only and never writes: changes go through
/// `tccutil`, which asks tccd. macOS lets a process open these files only
/// with Full Disk Access, so a refusal is reported as that, not as empty.
/// This is the pane's on-demand read; the watcher never opens them.
struct TCCDatabaseReader: PrivacyDatabaseReading {
    static let systemPath = "/Library/Application Support/com.apple.TCC/TCC.db"
    static func userPath(home: String) -> String {
        (home as NSString).appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
    }

    let systemPath: String
    let userPath: String

    init(systemPath: String = TCCDatabaseReader.systemPath,
         home: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.systemPath = systemPath
        self.userPath = Self.userPath(home: home)
    }

    init(systemPath: String, userPath: String) {
        self.systemPath = systemPath
        self.userPath = userPath
    }

    func read(_ database: PermissionRecord.Database) -> DatabaseReading {
        let path = database == .system ? systemPath : userPath
        // stat first: ENOENT is a missing database, EPERM the privacy
        // system refusing. FileManager.fileExists would fold both into false.
        var info = stat()
        if stat(path, &info) != 0 {
            let code = errno
            return .forOpenFailure(errno: code, detail: String(cString: strerror(code)))
        }

        var handle: OpaquePointer?
        let opened = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        defer { sqlite3_close_v2(handle) }
        guard opened == SQLITE_OK, let handle else {
            return failure(handle, fallback: "SQLite could not open the database (code \(opened)).")
        }
        sqlite3_busy_timeout(handle, 2000)

        do {
            let access = try records(handle, database: database, table: "access")
            let managed = try hasTable(handle, "managed_overrides")
                ? try records(handle, database: database, table: "managed_overrides")
                : []
            return .read(PermissionRecord.merging(access: access, managed: managed))
        } catch let error as ReadError {
            return failure(handle, fallback: error.message)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Queries

    private struct ReadError: Error { let message: String }

    /// Columns present in both tables since macOS 11.
    private static let columns = "service, client, client_type, auth_value, auth_reason, csreq, indirect_object_identifier, last_modified"

    private func records(_ handle: OpaquePointer, database: PermissionRecord.Database, table: String) throws -> [PermissionRecord] {
        let isManaged = table == "managed_overrides"
        var statement: OpaquePointer?
        let sql = "SELECT \(Self.columns) FROM \(table)"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ReadError(message: "Could not query \(table): \(message(handle)).")
        }
        defer { sqlite3_finalize(statement) }

        var result: [PermissionRecord] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw ReadError(message: "Reading \(table) stopped: \(message(handle)).") }
            // A row without a service, a client, a decision or a known client
            // type is not one the pane could explain; it is skipped, not guessed.
            guard let service = text(statement, 0), let client = text(statement, 1),
                  sqlite3_column_type(statement, 2) != SQLITE_NULL, sqlite3_column_type(statement, 3) != SQLITE_NULL,
                  let kind = PermissionRecord.ClientKind(clientType: Int(sqlite3_column_int64(statement, 2))) else { continue }
            let target = text(statement, 6).flatMap { $0 == "UNUSED" || $0.isEmpty ? nil : $0 }
            let modified = sqlite3_column_type(statement, 7) == SQLITE_NULL
                ? nil : Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 7)))
            result.append(PermissionRecord(
                database: database, service: service, client: client, clientKind: kind,
                decision: .init(authValue: Int(sqlite3_column_int64(statement, 3))),
                reason: Int(sqlite3_column_int64(statement, 4)),
                requirement: blob(statement, 5), target: target, lastModified: modified, isManaged: isManaged))
        }
        return result
    }

    private func hasTable(_ handle: OpaquePointer, _ name: String) throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw ReadError(message: "Could not list the database's tables: \(message(handle)).")
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, name, -1, Self.transient)
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw ReadError(message: "Could not list the database's tables: \(message(handle)).")
        }
    }

    // MARK: - Helpers

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }

    private func blob(_ statement: OpaquePointer, _ column: Int32) -> Data? {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: count)
    }

    private func message(_ handle: OpaquePointer?) -> String {
        guard let handle, let text = sqlite3_errmsg(handle) else { return "unknown error" }
        return String(cString: text)
    }

    /// SQLite reports a refused open as "unable to open"; the system errno
    /// says whether macOS's privacy protection refused it.
    private func failure(_ handle: OpaquePointer?, fallback: String) -> DatabaseReading {
        let code = handle.map { sqlite3_system_errno($0) } ?? 0
        if code == EPERM { return .needsFullDiskAccess }
        let detail = handle == nil ? fallback : "\(fallback) \(message(handle))"
        return code == 0 ? .failed(detail) : .forOpenFailure(errno: code, detail: detail)
    }
}
