import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A failed request, classified so the background check can report it as
/// the right kind of failure; the pane shows only the message.
public struct LookupFailure: LocalizedError, Equatable, Sendable, CustomStringConvertible {
    public enum Kind: Equatable, Sendable {
        /// The host did not answer: offline, DNS, refused, timed out.
        case unreachable
        /// The host answered with something that could not be read.
        case malformedResponse
        /// Skipped or refused to stay within a forge's request limit.
        case rateLimited
        /// Credentials were rejected, or could not be read without asking.
        case permissionDenied
        /// The source has no client yet (GitLab).
        case unsupported
        case failed
    }

    public let kind: Kind
    public let message: String

    public init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }

    public var errorDescription: String? { message }
    public var description: String { message }

    /// A transport error with the operation it interrupted:
    /// "Failed to fetch GitHub release: The Internet connection appears to be offline."
    static func network(_ error: Error, while operation: String) -> Error {
        if error is CancellationError { return error }
        if let urlError = error as? URLError, urlError.code == .cancelled { return CancellationError() }
        if let failure = error as? LookupFailure { return failure }
        return LookupFailure(.unreachable, "\(operation): \(error.localizedDescription)")
    }
}
