import Foundation

enum BackupError: LocalizedError {
    case invalid(String)
    case zenRunning
    case changed
    case unsafePath

    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .zenRunning: return "Quit Zen completely (⌘Q), then try again. A running browser can overwrite restored tabs."
        case .changed: return "This backup changed since its preview was loaded. Refresh and review it again before restoring."
        case .unsafePath: return "The profile contains a symbolic link or an unexpected file path. No session files were changed."
        }
    }
}
