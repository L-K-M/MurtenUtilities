import Foundation
import HallPassCore

enum PreferencesServiceError: LocalizedError {
    case cancelled, conflict, restored, rollbackFailed, commandFailed(String), verificationFailed

    var errorDescription: String? {
        switch self {
        case .cancelled: "The administrator dialog was cancelled."
        case .conflict: "The system settings were changed in the meantime. Reload them and make your changes again."
        case .restored: "Saving failed. The previous settings were restored."
        case .rollbackFailed: "The change could not be fully undone. Reload the system settings and restore the automatic backup if needed."
        case .commandFailed(let detail): "macOS could not run the command.\n\(detail)"
        case .verificationFailed: "The saved values do not match the preview. Reload the settings. The automatic backup remains available."
        }
    }
}

/// The privileged boundary: reads and writes both ask for administrator
/// access, so nothing here may back a watcher (docs/modules.md, HallPass).
protocol PreferencesServicing: Sendable {
    func load() async throws -> PreferencesSnapshot
    func save(_ plan: PreferencePlan) async throws -> PreferencesSnapshot
}

actor SystemPreferencesService: PreferencesServicing {
    func load() throws -> PreferencesSnapshot {
        let xml = try authorized(PreferencePlan.readCommand, prompt: "HallPass wants to read the local network exemptions.")
        return try PreferencesSnapshot(xml: xml)
    }

    func save(_ plan: PreferencePlan) throws -> PreferencesSnapshot {
        let xml = try authorized(plan.shellScript(), prompt: "HallPass wants to save the displayed network exemptions.")
        let result = try PreferencesSnapshot(xml: xml)
        guard result.configuration == plan.desired else { throw PreferencesServiceError.verificationFailed }
        return result
    }

    private func authorized(_ command: String, prompt: String) throws -> String {
        let source = "do shell script \(PreferencePlan.appleScriptString(command)) with prompt \(PreferencePlan.appleScriptString(prompt)) with administrator privileges without altering line endings"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        try process.run()
        input.fileHandleForWriting.write(Data(source.utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let result = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            if result.contains("(-128)") { throw PreferencesServiceError.cancelled }
            if result.contains("HALLPASS_CONFLICT") { throw PreferencesServiceError.conflict }
            if result.contains("HALLPASS_ROLLBACK_FAILED") { throw PreferencesServiceError.rollbackFailed }
            if result.contains("HALLPASS_WRITE_FAILED_RESTORED") { throw PreferencesServiceError.restored }
            throw PreferencesServiceError.commandFailed(String(result.prefix(1600)))
        }
        return result
    }
}
