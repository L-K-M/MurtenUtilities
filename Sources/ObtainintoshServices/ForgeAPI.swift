import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ObtainintoshCore

/// Request plumbing both forge clients share.
enum ForgeAPI {
    /// API calls give up after this long without data, so a hung connection
    /// cannot leave the pane stuck in "Checking…".
    static let requestTimeout: TimeInterval = 30

    static func request(_ url: String, accept: String, authorization: String?,
                        extraHeaders: [String: String] = [:]) throws -> URLRequest {
        guard let target = URL(string: url) else { throw LookupFailure(.failed, "Invalid repository URL: \(url)") }
        var request = URLRequest(url: target, timeoutInterval: requestTimeout)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(ObtainintoshUserAgent.value, forHTTPHeaderField: "User-Agent")
        for (name, value) in extraHeaders { request.setValue(value, forHTTPHeaderField: name) }
        if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
        return request
    }

    static func send(_ request: URLRequest, transport: HTTPTransport, operation: String) async throws -> HTTPResponse {
        do {
            return try await transport.data(request)
        } catch {
            throw LookupFailure.network(error, while: operation)
        }
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from response: HTTPResponse,
                                         operation: String) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: response.body)
        } catch {
            throw LookupFailure(.malformedResponse, "\(operation): \(error.localizedDescription)")
        }
    }

    /// One path segment of an API URL, percent-encoded: owner and repository
    /// names come from what the user typed.
    static func segment(_ text: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}
