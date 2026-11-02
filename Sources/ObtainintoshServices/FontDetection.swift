import Foundation
import ObtainintoshCore

/// The outcome of one font lookup.
public enum FontDetection: Equatable, Sendable {
    /// Not a font: the program detection stands.
    case notAFont
    case installed(InstalledVersion)
    case notInstalled
}
