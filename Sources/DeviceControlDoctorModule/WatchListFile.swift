import Foundation
import DoctorCore

/// The standalone app's watch list, read and written in place so the suite
/// and DeviceControlDoctor keep one list and one history:
/// `~/Library/Application Support/DeviceControlDoctor/watchlist.json`.
enum WatchListFile {
    struct SavedState: Codable { var schemaVersion: Int; var apps: [WatchedApp]; var events: [DoctorEvent] }

    enum ReadResult {
        /// No list saved yet: an empty watch list, not an error.
        case missing
        case loaded(SavedState)
        /// Present but unreadable or of an unknown schema. Never overwrite it.
        case unreadable(Error)
    }

    static let schemaVersion = 1

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeviceControlDoctor/watchlist.json")
    }

    static func read(at url: URL) -> ReadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            let data = try decoder().decode(SavedState.self, from: Data(contentsOf: url))
            guard data.schemaVersion == schemaVersion else { throw CocoaError(.fileReadCorruptFile) }
            return .loaded(data)
        } catch {
            return .unreadable(error)
        }
    }

    static func write(apps: [WatchedApp], events: [DoctorEvent], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder().encode(SavedState(schemaVersion: schemaVersion, apps: apps, events: events)).write(to: url, options: .atomic)
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601; return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder
    }
}
