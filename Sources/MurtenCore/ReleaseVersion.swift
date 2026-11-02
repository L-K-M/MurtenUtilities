import Foundation

/// A dotted numeric release version, e.g. "v1.2.0" or "1.10". Used to tell
/// whether a published release is newer than the running build.
public struct ReleaseVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let components: [Int]

    /// Accepts an optional leading "v" and up to four numeric components;
    /// pre-release suffixes ("-beta.1") are rejected rather than guessed.
    public init?(_ string: String) {
        var text = Substring(string.trimmingCharacters(in: .whitespaces))
        if text.first == "v" || text.first == "V" { text = text.dropFirst() }

        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }

        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), let number = Int(part), number >= 0 else { return nil }
            numbers.append(number)
        }
        components = numbers
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        let length = max(lhs.components.count, rhs.components.count)
        for index in 0..<length {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    public func hash(into hasher: inout Hasher) {
        var trimmed = components
        while trimmed.last == 0 { trimmed.removeLast() }
        hasher.combine(trimmed)
    }
}
