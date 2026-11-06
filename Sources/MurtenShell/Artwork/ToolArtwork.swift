import SwiftUI

/// Keep the registry's portable SF Symbols as fallbacks; artwork belongs to
/// the shell. A 128-point canvas keeps all ten drawings at the same scale.
enum ToolArtwork: String, CaseIterable {
    case dockerCleaner = "dockvac"
    case developerCleanup = "repomen"
    case startupManager = "bootcaptain"
    case permissionCheckup = "devicecontroldoctor"
    case shortcutDetective = "shortking"
    case networkAccess = "hallpass"
    case sessionRecovery = "zenbackupmanager"
    case softwareUpdates = "obtainintosh"
    case runnerManager = "runningman"
    case systemMonitor = "coreography"

    func draw(in context: GraphicsContext) {
        let drawing = ToolDrawing(context: context)
        switch self {
        case .dockerCleaner: drawing.dockerCleaner()
        case .developerCleanup: drawing.developerCleanup()
        case .startupManager: drawing.startupManager()
        case .permissionCheckup: drawing.permissionCheckup()
        case .shortcutDetective: drawing.shortcutDetective()
        case .networkAccess: drawing.networkAccess()
        case .sessionRecovery: drawing.sessionRecovery()
        case .softwareUpdates: drawing.softwareUpdates()
        case .runnerManager: drawing.runnerManager()
        case .systemMonitor: drawing.systemMonitor()
        }
    }
}
