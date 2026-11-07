import Foundation

enum ProcessTerminationError: LocalizedError {
    case unavailable
    case busy
    case protectedProcess
    case identityChanged
    case unreadableIdentity
    case signalFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "This quit action is not available for this process."
        case .busy:
            return "Another permission check or repair is running. Wait for it to finish."
        case .protectedProcess:
            return "Only your own processes can be force quit here. This app and system processes are protected."
        case .identityChanged:
            return "This process has exited or its identity changed. Refresh the list before trying again."
        case .unreadableIdentity:
            return "The process identity could not be verified. Nothing was force quit."
        case .signalFailed(let code):
            return "macOS rejected the Force Quit request (error \(code)). Nothing was force quit."
        }
    }
}
