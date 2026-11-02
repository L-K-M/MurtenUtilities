import Foundation
import Testing
@testable import HallPassCore

/// Executes the real generated shell against temporary plist domains only.
/// No real networking preferences, sudo, or administrator dialogs are used.
struct PreferencePlanTests {
    @Test func preservesMissingVersusEmpty() throws {
        let snapshot = try PreferencesSnapshot(configuration: .init(wifi: [], ethernet: nil))
        #expect(snapshot.configuration.wifi == [])
        #expect(snapshot.configuration.ethernet == nil)
    }

    @Test func rejectsUnexpectedPreferenceType() throws {
        let xml = try xmlString([NetworkInterface.wifi.key: "not an array"])
        #expect(throws: ConfigurationError.self) { try PreferencesSnapshot(xml: xml) }
    }

    @Test func updatesBothInterfacesAndPreservesUnmanagedKeys() throws {
        let fixture = try Fixture(values: ["Unmanaged": "leave me alone"])
        defer { fixture.cleanUp() }
        let baseline = try fixture.snapshot()
        let desired = NetworkConfiguration(wifi: ["192.168.1.0/24"], ethernet: ["fd12:3456::/32"])
        let plan = try PreferencePlan(baseline: baseline, desired: desired)
        let result = try fixture.execute(plan)
        #expect(result.status == 0, "\(result.output)")
        #expect(try fixture.snapshot().configuration == desired)
        #expect(try fixture.dictionary()["Unmanaged"] as? String == "leave me alone")
    }

    @Test func removingAnOverrideDeletesOnlyThatKey() throws {
        let fixture = try Fixture(values: [NetworkInterface.wifi.key: ["169.254.0.0/16"], "Other": true])
        defer { fixture.cleanUp() }
        let plan = try PreferencePlan(baseline: fixture.snapshot(), desired: .init())
        let result = try fixture.execute(plan)
        #expect(result.status == 0, "\(result.output)")
        #expect(try fixture.dictionary()[NetworkInterface.wifi.key] == nil)
        #expect(try fixture.dictionary()["Other"] as? Bool == true)
    }

    @Test func detectsStaleBaselineBeforeWriting() throws {
        let fixture = try Fixture(values: [NetworkInterface.wifi.key: ["169.254.0.0/16"]])
        defer { fixture.cleanUp() }
        let baseline = try fixture.snapshot()
        try fixture.seed([NetworkInterface.wifi.key: ["10.0.0.0/8"]])
        let plan = try PreferencePlan(baseline: baseline, desired: .init(wifi: ["192.168.1.0/24"]))
        let result = try fixture.execute(plan)
        #expect(result.status == 21)
        #expect(result.output.contains("HALLPASS_CONFLICT"))
        #expect(try fixture.snapshot().configuration.wifi == ["10.0.0.0/8"])
    }

    @Test func rollsBackWhenSecondWriteFailsAndQuotesOldData() throws {
        let fixture = try Fixture(values: [NetworkInterface.wifi.key: ["old'value; $(touch /tmp/HallPass-must-not-execute)"], "Other": 42])
        defer { fixture.cleanUp() }
        let baseline = try fixture.snapshot()
        let plan = try PreferencePlan(baseline: baseline, desired: .init(wifi: ["10.0.0.0/8"], ethernet: ["169.254.0.0/16"]))
        let shim = """
        #!/bin/sh
        if [ "$1" = write ] && [ "$3" = AllowedEthernetLocalNetworkAddresses ] && [ ! -f \(PreferencePlan.shellQuote(fixture.directory.appendingPathComponent("failed").path)) ]; then
            /usr/bin/touch \(PreferencePlan.shellQuote(fixture.directory.appendingPathComponent("failed").path))
            exit 7
        fi
        exec /usr/bin/defaults "$@"
        """
        let result = try fixture.execute(plan, shim: shim)
        #expect(result.status == 22, "\(result.output)")
        #expect(result.output.contains("HALLPASS_WRITE_FAILED_RESTORED"))
        #expect(try fixture.snapshot().configuration == baseline.configuration)
        #expect(try fixture.dictionary()["Other"] as? Int == 42)
        #expect(!FileManager.default.fileExists(atPath: "/tmp/HallPass-must-not-execute"))
    }

    @Test func readBackDetectsSilentlyIgnoredWrite() throws {
        let fixture = try Fixture(values: [:])
        defer { fixture.cleanUp() }
        let plan = try PreferencePlan(baseline: fixture.snapshot(), desired: .init(wifi: ["10.0.0.0/8"]))
        let shim = """
        #!/bin/sh
        if [ "$1" = write ]; then exit 0; fi
        exec /usr/bin/defaults "$@"
        """
        let result = try fixture.execute(plan, shim: shim)
        #expect(result.status == 22, "\(result.output)")
        #expect(try fixture.snapshot().configuration.wifi == nil)
    }

    @Test func backupRoundTripAndRejectsUnknownVersion() throws {
        let configuration = NetworkConfiguration(wifi: [], ethernet: ["fe80::/10"])
        let data = try ConfigurationBackup(configuration: configuration).encoded()
        #expect(try ConfigurationBackup.decode(data).configuration == configuration)
        let altered = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"formatVersion\" : 1", with: "\"formatVersion\" : 99")
        #expect(throws: ConfigurationError.self) { try ConfigurationBackup.decode(Data(altered.utf8)) }
    }

    @Test func doesNotClaimSuccessForIgnoredRollback() throws {
        let fixture = try Fixture(values: [NetworkInterface.wifi.key: ["169.254.0.0/16"]])
        defer { fixture.cleanUp() }
        let marker = PreferencePlan.shellQuote(fixture.directory.appendingPathComponent("failed").path)
        let plan = try PreferencePlan(baseline: fixture.snapshot(), desired: .init(wifi: ["10.0.0.0/8"], ethernet: ["192.168.1.0/24"]))
        let shim = """
        #!/bin/sh
        if [ "$1" = write ] && [ "$3" = AllowedEthernetLocalNetworkAddresses ] && [ ! -f \(marker) ]; then
            /usr/bin/touch \(marker)
            exit 7
        fi
        if [ "$1" = write ] && [ "$3" = AllowedWiFiLocalNetworkAddresses ] && [ -f \(marker) ]; then exit 0; fi
        exec /usr/bin/defaults "$@"
        """
        let result = try fixture.execute(plan, shim: shim)
        #expect(result.status == 23, "\(result.output)")
        #expect(result.output.contains("HALLPASS_ROLLBACK_FAILED"))
        #expect(try fixture.snapshot().configuration.wifi == ["10.0.0.0/8"])
    }

    @Test func restoresOtherKeyWhenOneRollbackConflicts() throws {
        let fixture = try Fixture(values: [:])
        defer { fixture.cleanUp() }
        let marker = PreferencePlan.shellQuote(fixture.directory.appendingPathComponent("failed").path)
        let plan = try PreferencePlan(baseline: fixture.snapshot(), desired: .init(wifi: ["10.0.0.0/8"], ethernet: ["192.168.1.0/24"]))
        let shim = """
        #!/bin/sh
        if [ "$1" = write ] && [ "$3" = AllowedEthernetLocalNetworkAddresses ] && [ ! -f \(marker) ]; then
            /usr/bin/defaults "$@" || exit 1
            /usr/bin/defaults write "$2" AllowedWiFiLocalNetworkAddresses -array '172.16.0.0/12' || exit 1
            /usr/bin/touch \(marker)
            exit 7
        fi
        exec /usr/bin/defaults "$@"
        """
        let result = try fixture.execute(plan, shim: shim)
        #expect(result.status == 23, "\(result.output)")
        #expect(try fixture.snapshot().configuration.wifi == ["172.16.0.0/12"])
        #expect(try fixture.snapshot().configuration.ethernet == nil)
    }

    @Test func backupCanReopenLegacyValuesForInspection() throws {
        let configuration = NetworkConfiguration(wifi: ["legacy-invalid-value"], ethernet: nil)
        let data = try ConfigurationBackup(configuration: configuration).encoded()
        #expect(try ConfigurationBackup.decode(data).configuration == configuration)
        #expect(throws: CIDRError.self) { try configuration.validate() }
    }
}

private func xmlString(_ dictionary: [String: Any]) throws -> String {
    String(decoding: try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0), as: UTF8.self)
}

private struct Fixture {
    let directory: URL
    var domain: String { directory.appendingPathComponent("preferences").path }

    init(values: [String: Any]) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("HallPassTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try seed(values)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: directory) }

    func seed(_ values: [String: Any]) throws {
        let result = try run("/usr/bin/defaults", ["import", domain, "-"], input: xmlString(values))
        guard result.status == 0 else { throw TestFailure.failed(result.output) }
    }

    func snapshot() throws -> PreferencesSnapshot {
        let result = try run("/usr/bin/defaults", ["export", domain, "-"])
        guard result.status == 0 else { throw TestFailure.failed(result.output) }
        return try PreferencesSnapshot(xml: result.output)
    }

    func dictionary() throws -> [String: Any] {
        try PropertyListSerialization.propertyList(from: Data(snapshot().xml.utf8), format: nil) as! [String: Any]
    }

    func execute(_ plan: PreferencePlan, shim: String? = nil) throws -> (status: Int32, output: String) {
        var script = try plan.shellScript().replacingOccurrences(of: PreferencePlan.shellQuote(PreferencePlan.domain), with: PreferencePlan.shellQuote(domain))
        if let shim {
            let url = directory.appendingPathComponent("defaults-shim")
            try Data(shim.utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            script = script.replacingOccurrences(of: "/usr/bin/defaults", with: PreferencePlan.shellQuote(url.path))
        }
        return try run("/bin/sh", ["-c", script])
    }
}

private enum TestFailure: Error { case failed(String) }

private func run(_ executable: String, _ arguments: [String], input: String? = nil) throws -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    if let input {
        let pipe = Pipe()
        process.standardInput = pipe
        try process.run()
        pipe.fileHandleForWriting.write(Data(input.utf8))
        try pipe.fileHandleForWriting.close()
    } else { try process.run() }
    let result = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: result, as: UTF8.self))
}
