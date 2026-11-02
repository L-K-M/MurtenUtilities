import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ObtainintoshServices

/// A stand-in for a forge: answers with canned responses in order and
/// records what was asked, so URL building, fallbacks and authentication are
/// exercised without a network. The port of the Rust tests' `mock_forge`.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    enum Response {
        /// A status and a JSON body in which `{address}` stands for the fake's address.
        case json(Int, String)
        /// A file served like a forge serves one: a `Range` request gets 206
        /// and just those bytes.
        case file([UInt8])
        /// A file served whole, as by a server that ignores `Range`.
        case wholeFile([UInt8])
        /// A status with a body delivered in these chunks.
        case chunks(Int, [Data])
        /// The connection fails.
        case failure(Error)
    }

    struct Recorded {
        let url: URL
        let authorization: String?
        let range: String?

        /// Path and query, as the Rust tests compared them.
        var target: String {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = nil
            components?.host = nil
            components?.port = nil
            return components?.string ?? url.absoluteString
        }
    }

    let address: String
    private let lock = NSLock()
    private var responses: [Response]
    private var recorded: [Recorded] = []

    init(address: String = "http://forge.test", _ responses: [Response]) {
        self.address = address
        self.responses = responses
    }

    var requests: [Recorded] {
        lock.withLock { recorded }
    }

    func stream(_ request: URLRequest) async throws -> HTTPStream {
        let next: Response? = lock.withLock {
            recorded.append(Recorded(url: request.url!, authorization: request.value(forHTTPHeaderField: "Authorization"),
                                     range: request.value(forHTTPHeaderField: "Range")))
            return responses.isEmpty ? nil : responses.removeFirst()
        }
        guard let next else { throw URLError(.cannotConnectToHost) }

        switch next {
        case .json(let status, let body):
            return Self.stream(status, [Data(body.replacingOccurrences(of: "{address}", with: address).utf8)])
        case .file(let bytes):
            guard let range = request.value(forHTTPHeaderField: "Range") else { return Self.stream(200, [Data(bytes)]) }
            return Self.stream(206, Self.chunked(Self.ranged(bytes, range)))
        case .wholeFile(let bytes):
            return Self.stream(200, Self.chunked(bytes))
        case .chunks(let status, let chunks):
            return Self.stream(status, chunks)
        case .failure(let error):
            throw error
        }
    }

    private static func stream(_ status: Int, _ chunks: [Data]) -> HTTPStream {
        let body = AsyncThrowingStream<Data, Error> { continuation in
            for chunk in chunks { continuation.yield(chunk) }
            continuation.finish()
        }
        return HTTPStream(status: status, headers: ["Content-Type": "application/json"], body: body)
    }

    /// Small chunks, so readers that stop early are exercised.
    private static func chunked(_ bytes: [UInt8]) -> [Data] {
        stride(from: 0, to: bytes.count, by: 1024).map { Data(bytes[$0..<min($0 + 1024, bytes.count)]) }
    }

    /// The bytes a `bytes=<first>-<last>` range selects, clipped to the file.
    private static func ranged(_ file: [UInt8], _ range: String) -> [UInt8] {
        let bounds = range.dropFirst("bytes=".count).split(separator: "-").compactMap { Int($0) }
        let end = min(bounds[1] + 1, file.count)
        return Array(file[min(bounds[0], end)..<end])
    }
}
