import Foundation

/// An error with a user-presentable message, the counterpart of the
/// standalone app's error strings.
public struct ObtainintoshError: LocalizedError, Equatable, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
    public var description: String { message }
}
