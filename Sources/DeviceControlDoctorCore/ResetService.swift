import Foundation

/// Resettable permissions have a broader scope than the keyboard/input
/// permissions managed by the watch list and its functional Test Pad.
/// Both scoped and service-wide repair plans use this roster.
public enum ResetService: String, CaseIterable, Identifiable, Sendable {
    case accessibility = "Accessibility"
    case postEvent = "PostEvent"
    case listenEvent = "ListenEvent"
    case screenCapture = "ScreenCapture"
    /// System-audio-only access is separate from screen capture and microphone access.
    case audioCapture = "AudioCapture"

    public init(_ permission: PermissionService) {
        switch permission {
        case .accessibility: self = .accessibility
        case .postEvent: self = .postEvent
        case .listenEvent: self = .listenEvent
        }
    }

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accessibility: return PermissionService.accessibility.title
        case .postEvent: return PermissionService.postEvent.title
        case .listenEvent: return PermissionService.listenEvent.title
        case .screenCapture: return "Screen & System Audio Recording"
        case .audioCapture: return "System Audio Recording Only"
        }
    }

    public var settingsAnchor: String {
        switch self {
        case .accessibility: return PermissionService.accessibility.settingsAnchor
        case .postEvent: return PermissionService.postEvent.settingsAnchor
        case .listenEvent: return PermissionService.listenEvent.settingsAnchor
        case .screenCapture, .audioCapture: return "Privacy_ScreenCapture"
        }
    }
}
