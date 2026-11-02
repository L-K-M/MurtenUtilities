import Foundation

/// Reads a file Shortking's `JSONStore` wrote, without writing anything.
///
/// `JSONStore.load()` moves an unreadable or newer file aside, which is right for
/// the pane that owns the file and wrong for anything that only looks: the
/// suite's background watcher and the one-time settings import. Those read
/// through here and report a problem instead of repairing it.
public enum StoreFileReader {

    /// The newest envelope this build understands; `JSONStore.currentSchemaVersion`.
    public static let supportedSchemaVersion = 1

    public enum ReadError: Error, Equatable {
        /// Written by a newer Shortking; left alone.
        case newerSchema(Int)
        /// Not a store envelope, or a payload of another shape.
        case malformed
    }

    private struct Header: Decodable {
        var schemaVersion: Int
    }

    private struct Envelope<Payload: Decodable>: Decodable {
        var schemaVersion: Int
        var payload: Payload
    }

    /// The payload of a `JSONStore` file: `{schemaVersion, writtenAt, payload}`
    /// with ISO 8601 dates.
    public static func payload<Payload: Decodable>(_ type: Payload.Type, from data: Data) throws -> Payload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // The version first, so a newer file reads as newer rather than malformed.
        guard let header = try? decoder.decode(Header.self, from: data) else { throw ReadError.malformed }
        guard header.schemaVersion <= supportedSchemaVersion else {
            throw ReadError.newerSchema(header.schemaVersion)
        }

        do {
            return try decoder.decode(Envelope<Payload>.self, from: data).payload
        } catch {
            throw ReadError.malformed
        }
    }
}
