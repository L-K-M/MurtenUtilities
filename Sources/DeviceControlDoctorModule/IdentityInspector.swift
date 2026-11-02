import Foundation
import DoctorCore

struct IdentityInspector {
    let runner: any ProcessRunning

    init(runner: any ProcessRunning = ProcessRunner()) {
        self.runner = runner
    }

    func inspect(path: String) async -> AppIdentity {
        var identity = AppIdentity()
        let display = await runner.run(SystemTool.codesign, ["--display", "--verbose=2", "-r", "-", path])
        for line in display.output.components(separatedBy: .newlines) {
            if line.hasPrefix("Identifier=") { identity.signingIdentifier = String(line.dropFirst("Identifier=".count)) }
            if line.hasPrefix("TeamIdentifier=") { identity.teamIdentifier = String(line.dropFirst("TeamIdentifier=".count)) }
            if line.hasPrefix("designated =>") { identity.requirement = String(line.dropFirst("designated =>".count)).trimmingCharacters(in: .whitespaces) }
        }
        let verify = await runner.run(SystemTool.codesign, ["--verify", "--strict", "--verbose=2", path])
        identity.signatureValid = verify.timedOut ? nil : verify.exitCode == 0
        identity.signatureDetail = verify.timedOut ? "Signature check timed out" : (verify.output.isEmpty ? (verify.exitCode == 0 ? "Signature verified" : "Could not verify signature") : String(verify.output.prefix(1800)))
        return identity
    }
}
