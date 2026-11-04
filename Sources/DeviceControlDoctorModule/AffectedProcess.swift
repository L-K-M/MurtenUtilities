import Foundation

struct AffectedProcess: Identifiable, Equatable, Sendable {
    let processIdentifier: Int32
    let name: String
    let executablePath: String
    let canRequestTermination: Bool

    var id: Int32 { processIdentifier }
}
