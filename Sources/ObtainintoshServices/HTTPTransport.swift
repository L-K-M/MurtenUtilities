import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The only way the services reach the network, so tests can answer with
/// fixtures and record what was asked. Implementations drop an
/// `Authorization` header when a redirect leaves the request's origin.
public protocol HTTPTransport: Sendable {
    func stream(_ request: URLRequest) async throws -> HTTPStream
}

extension HTTPTransport {
    /// The whole body, refusing one larger than `limit` bytes.
    public func data(_ request: URLRequest, limit: Int = 16 * 1024 * 1024) async throws -> HTTPResponse {
        let response = try await stream(request)
        var body = Data()
        for try await chunk in response.body {
            body.append(chunk)
            guard body.count <= limit else {
                throw LookupFailure(.malformedResponse, "The server sent more data than expected")
            }
        }
        return HTTPResponse(status: response.status, headers: response.headers, body: body)
    }
}
