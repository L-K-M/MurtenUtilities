import SwiftUI
import RepoMenCore

/// The category colors the sidebar and table share. They live with the views so
/// RepoMenCore stays free of SwiftUI.
extension ArtifactCategory {
    var tint: Color {
        switch self {
        case .projects: return .orange
        case .developer: return .blue
        case .packageManagers: return .brown
        case .browsers: return .teal
        case .applications: return .purple
        case .system: return .red
        }
    }
}
