import Foundation

/// How a check finds where a font is installed.
public enum FontLookup: Equatable, Sendable {
    /// The lookup named the font's file, so the font folders are searched.
    case named(String)
    /// The lookup failed; the copy found last time is read again, so the
    /// installed version stays known while the forge cannot be reached.
    case lastFoundAt(String)
}
