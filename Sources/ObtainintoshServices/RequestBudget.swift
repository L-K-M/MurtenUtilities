import Foundation

/// Meters the requests one check sends to a rate-limited API. The GitHub
/// client asks before each API request and reports each response's limit
/// headers; the pane's own checks run without a budget, as the standalone
/// app's did.
public protocol RequestBudget: Sendable {
    /// Throws a `rateLimited` failure when the request must not be sent.
    func spend() async throws
    /// Reads `x-ratelimit-remaining` from a response.
    func record(headers: [String: String]) async
}
