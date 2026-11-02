import Foundation

/// A whole response, for API calls.
public struct HTTPResponse: Sendable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data

    public var isSuccess: Bool { (200..<300).contains(status) }
}
