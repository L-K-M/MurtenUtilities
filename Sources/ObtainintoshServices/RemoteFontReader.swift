import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ObtainintoshCore

/// Reads the version a font on a forge declares with range requests: the
/// table directory, then the table holding the version. A font of a few
/// megabytes costs a few kilobytes to check.
enum RemoteFontReader {
    /// The version the font at `url` declares. `authorization` is the
    /// header its download would carry, if any.
    static func readVersion(url: String, transport: HTTPTransport, authorization: String?) async throws -> String {
        var reader = FontVersionReader()
        var step = reader.start()
        while true {
            switch step {
            case .version(let version):
                return version
            case .read(let range):
                let bytes = try await readRange(url: url, range: range, transport: transport, authorization: authorization)
                do {
                    step = try reader.advance(bytes)
                } catch {
                    throw LookupFailure(.malformedResponse, "Could not read the version of \(url): \(error.localizedDescription)")
                }
            }
        }
    }

    /// Bytes `range` of a file, or as many of them as the file has.
    private static func readRange(url: String, range: Range<UInt64>, transport: HTTPTransport,
                                  authorization: String?) async throws -> [UInt8] {
        guard !range.isEmpty else { return [] }
        guard let target = URL(string: url) else { throw LookupFailure(.failed, "Invalid font URL: \(url)") }

        var request = URLRequest(url: target, timeoutInterval: 30)
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        request.setValue(ObtainintoshUserAgent.value, forHTTPHeaderField: "User-Agent")
        if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }

        let response: HTTPStream
        do {
            response = try await transport.stream(request)
        } catch {
            throw LookupFailure.network(error, while: "Failed to fetch the font file")
        }

        var skip: UInt64
        switch response.status {
        case 206:
            skip = 0
        case 200:
            // A server that ignores ranges sends the whole file: skip to the
            // range, and stop reading once it is in.
            skip = range.lowerBound
        case 416:
            // The range starts past the end of the file.
            response.cancel()
            return []
        default:
            response.cancel()
            throw LookupFailure(.failed, "Failed to fetch the font file: HTTP \(ForgeMessages.statusText(response.status))")
        }

        let wanted = Int(range.upperBound - range.lowerBound)
        var bytes: [UInt8] = []
        do {
            for try await chunk in response.body {
                let skipped = Int(min(skip, UInt64(chunk.count)))
                skip -= UInt64(skipped)
                bytes.append(contentsOf: chunk.dropFirst(skipped))
                if bytes.count >= wanted { break }
            }
        } catch {
            throw LookupFailure.network(error, while: "Failed to read the font file")
        }
        response.cancel()
        return Array(bytes.prefix(wanted))
    }
}
