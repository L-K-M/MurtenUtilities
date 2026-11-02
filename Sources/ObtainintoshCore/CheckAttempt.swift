import Foundation

/// How the last update check for a program turned out. Stored on the program
/// so the pane can tell "checked, up to date" apart from "the check never
/// completed", which a bare `latestVersion` cannot express.
public enum CheckAttemptState: String, Codable, Sendable {
    case succeeded
    case failed
    case unsupported
}

public struct CheckAttempt: Codable, Equatable, Sendable {
    public var attemptedAt: String
    public var state: CheckAttemptState
    public var message: String?

    private enum CodingKeys: String, CodingKey {
        case attemptedAt = "attempted_at"
        case state
        case message
    }

    public init(attemptedAt: String, state: CheckAttemptState, message: String? = nil) {
        self.attemptedAt = attemptedAt
        self.state = state
        self.message = message
    }

    public static func succeeded(at attemptedAt: String) -> CheckAttempt {
        CheckAttempt(attemptedAt: attemptedAt, state: .succeeded)
    }

    public static func unsuccessful(at attemptedAt: String, state: CheckAttemptState, message: String) -> CheckAttempt {
        assert(state != .succeeded, "an unsuccessful attempt cannot be a success")
        return CheckAttempt(attemptedAt: attemptedAt, state: state, message: boundedCheckMessage(message))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attemptedAt = try container.decode(String.self, forKey: .attemptedAt)
        state = try container.decode(CheckAttemptState.self, forKey: .state)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }
}

/// Collapses whitespace and caps length. These messages come from network and
/// forge errors, go into the data file and are shown in a tooltip, none of
/// which wants an unbounded multi-line string.
public func boundedCheckMessage(_ message: String) -> String {
    let maximumCharacters = 240
    let ellipsis = "..."

    let normalized = message.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    if normalized.count <= maximumCharacters { return normalized }

    return String(normalized.prefix(maximumCharacters - ellipsis.count)) + ellipsis
}
