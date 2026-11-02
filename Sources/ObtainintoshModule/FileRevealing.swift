import Foundation

/// Shows a downloaded file in Finder. The module never opens or installs it.
protocol FileRevealing: Sendable {
    /// Whether Finder showed the file.
    @MainActor func reveal(_ url: URL) -> Bool
}
