import Foundation

/// A response whose body arrives in chunks. Stopping the iteration early, or
/// calling `cancel`, cancels the request, so a range read against a server
/// that ignores ranges does not download the whole file.
public struct HTTPStream: Sendable {
    public let status: Int
    /// Header names lowercased.
    public let headers: [String: String]
    public let body: AsyncThrowingStream<Data, Error>
    /// Abandons the body without reading it.
    public let cancel: @Sendable () -> Void

    public init(status: Int, headers: [String: String], body: AsyncThrowingStream<Data, Error>,
                cancel: @escaping @Sendable () -> Void = {}) {
        self.status = status
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
        self.body = body
        self.cancel = cancel
    }

    public var isSuccess: Bool { (200..<300).contains(status) }
}
