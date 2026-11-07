import Foundation

struct AffectedProcess: Identifiable, Equatable, Sendable {
    let processIdentifier: Int32
    let name: String
    let executablePath: String
    let canRequestTermination: Bool
    let startTime: ProcessStartTime?
    let canForceTerminate: Bool

    init(processIdentifier: Int32, name: String, executablePath: String,
         canRequestTermination: Bool, startTime: ProcessStartTime? = nil,
         canForceTerminate: Bool = false) {
        self.processIdentifier = processIdentifier
        self.name = name
        self.executablePath = executablePath
        self.canRequestTermination = canRequestTermination
        self.startTime = startTime
        self.canForceTerminate = canForceTerminate
    }

    var id: Int32 { processIdentifier }
}
