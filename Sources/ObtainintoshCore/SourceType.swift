import Foundation

/// The forge a tracked program's releases come from. Stored lowercase, as the
/// standalone app's `apps.json` and program-list files spell it.
public enum SourceType: String, Codable, Sendable, CaseIterable {
    case github
    case gitlab
    case forgejo

    /// The name shown in the Add Program dialog.
    public var displayName: String {
        switch self {
        case .github: return "GitHub"
        case .gitlab: return "GitLab"
        case .forgejo: return "Forgejo"
        }
    }

    // A hand-edited program list names the forge itself, so an unknown value
    // is reported in words rather than as a generic decoding failure.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = SourceType(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "unknown variant `\(raw)`, expected one of `github`, `gitlab`, `forgejo`")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
