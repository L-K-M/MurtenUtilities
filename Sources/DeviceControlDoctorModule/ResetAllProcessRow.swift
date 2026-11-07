import Foundation

struct ResetAllProcessRow: Identifiable {
    struct ID: Hashable {
        let processIdentifier: Int32
        let executablePath: String
        let startTime: ProcessStartTime?
    }

    enum State: String {
        case running = "Running"
        case quitRequested = "Quit requested"
        case forceQuitRequested = "Force quit requested"
        case stillRunning = "Still running"
        case exited = "Exited"
        case unverified = "Status unavailable"
    }

    let process: AffectedProcess
    var state: State
    var detail: String?

    var id: ID {
        ID(processIdentifier: process.processIdentifier, executablePath: process.executablePath,
           startTime: process.startTime)
    }

    var isRunning: Bool { state != .exited && state != .unverified }
}
