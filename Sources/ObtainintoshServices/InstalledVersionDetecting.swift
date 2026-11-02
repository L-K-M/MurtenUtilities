import Foundation
import ObtainintoshCore

/// Finds installed copies of tracked programs and fonts. Only reads the file
/// system; never prompts.
public protocol InstalledVersionDetecting: Sendable {
    func detectPrograms(_ apps: [TrackedApp]) async -> [InstalledVersion?]
    func detectFonts(_ lookups: [FontLookup?]) async -> [FontDetection]
}
