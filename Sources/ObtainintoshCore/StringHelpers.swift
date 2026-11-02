import Foundation

// MARK: - ASCII-only text helpers
//
// Hosts, URL schemes and release asset names are compared the way the
// standalone app's Rust code does: ASCII case folding only, so a non-ASCII
// letter is never folded into a different ASCII one.

extension String {
    /// Lowercases ASCII letters only.
    func asciiLowercased() -> String {
        String(String.UnicodeScalarView(unicodeScalars.map { scalar in
            ("A"..."Z").contains(scalar) ? Unicode.Scalar(scalar.value + 32)! : scalar
        }))
    }

    /// Removes every trailing occurrence of `suffix`, like Rust's
    /// `trim_end_matches` with a string pattern.
    func trimmingSuffixRepeatedly(_ suffix: String) -> String {
        guard !suffix.isEmpty else { return self }
        var result = self
        while result.hasSuffix(suffix) { result.removeLast(suffix.count) }
        return result
    }

    /// The text before the first `?` or `#`: a URL part without its query
    /// string or fragment.
    func beforeQueryOrFragment() -> String {
        String(prefix { $0 != "?" && $0 != "#" })
    }

    /// Splits on whitespace runs and joins with single spaces.
    func collapsingWhitespace() -> String {
        split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
    var isASCIIAlphanumeric: Bool { isASCII && (isLetter || isNumber) }
    var isASCIIHexDigit: Bool { isASCII && isHexDigit }
}
