import Foundation

/// How the standalone app's table compared an installed version with the
/// latest release: semver where both parse, coerced semver where both
/// contain a number, and a numeric-aware text comparison otherwise, so
/// "10.0" is newer than "9.0".
public enum VersionComparison {
    /// Whether `latest` is newer than `current`. False when either is
    /// unknown: a program that is not installed has no update.
    public static func hasUpdate(current: String?, latest: String?) -> Bool {
        guard let current, !current.isEmpty, let latest, !latest.isEmpty else { return false }
        return compare(cleaned(latest), cleaned(current)) == .orderedDescending
    }

    /// Orders two version strings for sorting; an unknown version sorts first.
    public static func compareForSorting(_ left: String?, _ right: String?) -> ComparisonResult {
        let left = cleaned(left ?? "")
        let right = cleaned(right ?? "")
        switch (left.isEmpty, right.isEmpty) {
        case (true, true): return .orderedSame
        case (true, false): return .orderedAscending
        case (false, true): return .orderedDescending
        case (false, false): return compare(left, right)
        }
    }

    private static func compare(_ left: String, _ right: String) -> ComparisonResult {
        if let a = SemanticVersion(strict: left), let b = SemanticVersion(strict: right) {
            return SemanticVersion.compare(a, b)
        }
        if let a = SemanticVersion.coerce(left), let b = SemanticVersion.coerce(right) {
            return SemanticVersion.compare(a, b)
        }
        return collate(left, right)
    }

    /// Removes one leading lowercase "v", then surrounding whitespace, as the
    /// table did (`v.replace(/^v/, '').trim()`).
    static func cleaned(_ version: String) -> String {
        let stripped = version.hasPrefix("v") ? String(version.dropFirst()) : version
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Numeric-aware, case- and accent-insensitive text order: the
    /// counterpart of `Intl.Collator(undefined, {numeric: true,
    /// sensitivity: 'base'})`.
    public static func collate(_ left: String, _ right: String) -> ComparisonResult {
        left.compare(right, options: [.numeric, .caseInsensitive, .diacriticInsensitive, .widthInsensitive])
    }
}
