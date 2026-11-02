import Foundation

/// The subset of node-semver (7.x, non-loose) the standalone app's table used
/// to decide "update available": strict parsing, `coerce` and precedence.
/// Ported so the suite flags exactly the versions the standalone app did.
public struct SemanticVersion: Comparable, Sendable {
    /// node-semver refuses longer inputs outright.
    static let maximumLength = 256
    /// node-semver's MAX_SAFE_INTEGER bound on numeric components.
    static let maximumComponent: UInt64 = 9_007_199_254_740_991

    enum Identifier: Equatable, Sendable {
        case numeric(UInt64)
        case alphanumeric(String)
    }

    let major: UInt64
    let minor: UInt64
    let patch: UInt64
    let prerelease: [Identifier]

    // MARK: - Parsing

    /// `semver.valid`: `1.2.3`, `v1.2.3-beta.1+build`; no leading zeros.
    public init?(strict text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= Self.maximumLength else { return nil }
        var rest = Substring(text)
        if rest.first == "v" { rest = rest.dropFirst() }

        // Build metadata never affects precedence; it only has to be well formed.
        if let plus = rest.firstIndex(of: "+") {
            let build = rest[rest.index(after: plus)...]
            guard Self.isDottedIdentifierList(build) else { return nil }
            rest = rest[..<plus]
        }

        var prerelease: [Identifier] = []
        if let dash = rest.firstIndex(of: "-") {
            let text = rest[rest.index(after: dash)...]
            guard Self.isDottedIdentifierList(text) else { return nil }
            for part in text.split(separator: ".", omittingEmptySubsequences: false) {
                if part.allSatisfy(\.isASCIIDigit) {
                    guard let number = Self.numericIdentifier(part) else { return nil }
                    prerelease.append(.numeric(number))
                } else {
                    prerelease.append(.alphanumeric(String(part)))
                }
            }
            rest = rest[..<dash]
        }

        let main = rest.split(separator: ".", omittingEmptySubsequences: false)
        guard main.count == 3, let major = Self.numericIdentifier(main[0]), let minor = Self.numericIdentifier(main[1]),
              let patch = Self.numericIdentifier(main[2]) else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// `semver.coerce`: the first run of up to three dotted numbers in the
    /// text (`Version 2.4 beta` → 2.4.0), parsed strictly, so a leading zero
    /// still yields nil.
    public static func coerce(_ text: String) -> SemanticVersion? {
        let pattern = "(^|[^0-9])([0-9]{1,16})(?:\\.([0-9]{1,16}))?(?:\\.([0-9]{1,16}))?(?:$|[^0-9])"
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
            return String(text[swiftRange])
        }
        guard let major = group(2) else { return nil }
        return SemanticVersion(strict: "\(major).\(group(3) ?? "0").\(group(4) ?? "0")")
    }

    /// `0` or a number without a leading zero, within the safe-integer range.
    private static func numericIdentifier(_ text: Substring) -> UInt64? {
        guard !text.isEmpty, text.allSatisfy(\.isASCIIDigit) else { return nil }
        guard text == "0" || text.first != "0" else { return nil }
        guard let value = UInt64(text), value <= maximumComponent else { return nil }
        return value
    }

    /// Dot-separated, non-empty identifiers of `[0-9A-Za-z-]`.
    private static func isDottedIdentifierList(_ text: Substring) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isASCIIAlphanumeric || $0 == "-" }
        }
    }

    // MARK: - Precedence

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        compare(lhs, rhs) == .orderedAscending
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        compare(lhs, rhs) == .orderedSame
    }

    /// Main version first; a prerelease sorts before its release; numeric
    /// identifiers sort numerically and before alphanumeric ones.
    public static func compare(_ lhs: SemanticVersion, _ rhs: SemanticVersion) -> ComparisonResult {
        for (left, right) in [(lhs.major, rhs.major), (lhs.minor, rhs.minor), (lhs.patch, rhs.patch)] where left != right {
            return left < right ? .orderedAscending : .orderedDescending
        }

        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true): return .orderedSame
        case (false, true): return .orderedAscending
        case (true, false): return .orderedDescending
        case (false, false): break
        }

        for index in 0..<max(lhs.prerelease.count, rhs.prerelease.count) {
            guard index < lhs.prerelease.count else { return .orderedAscending }
            guard index < rhs.prerelease.count else { return .orderedDescending }
            switch (lhs.prerelease[index], rhs.prerelease[index]) {
            case (.numeric(let left), .numeric(let right)) where left != right:
                return left < right ? .orderedAscending : .orderedDescending
            case (.numeric, .alphanumeric):
                return .orderedAscending
            case (.alphanumeric, .numeric):
                return .orderedDescending
            case (.alphanumeric(let left), .alphanumeric(let right)) where left != right:
                return left.utf8.lexicographicallyPrecedes(right.utf8) ? .orderedAscending : .orderedDescending
            default:
                continue
            }
        }
        return .orderedSame
    }
}
