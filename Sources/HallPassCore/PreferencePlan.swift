import Foundation

/// Only this fixed preference domain and these two keys may be changed.
public struct PreferencePlan: Sendable {
    public static let domain = "com.apple.network.local-network"
    public let baseline: PreferencesSnapshot
    public let desired: NetworkConfiguration

    public init(baseline: PreferencesSnapshot, desired: NetworkConfiguration) throws {
        try desired.validate()
        self.baseline = baseline
        self.desired = desired
    }

    public var changedInterfaces: [NetworkInterface] {
        NetworkInterface.allCases.filter { baseline.configuration[$0] != desired[$0] }
    }

    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    public static func appleScriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    public static var readCommand: String { "/usr/bin/defaults export \(shellQuote(domain)) -" }

    /// No user-provided command, executable, domain, or key is accepted.
    /// XML is data, shell quoted, and is never evaluated as source code.
    public func shellScript() throws -> String {
        let desiredXML = try PreferencesSnapshot(configuration: desired).xml
        let changes = changedInterfaces
        let rollback = try changes.map { interface in
            """
            if [ "$touched_\(interface.rawValue)" -eq 1 ]; then
                restore_failed=0
                rollback_current=$(\(Self.readCommand)) || restore_failed=1
                if [ "$restore_failed" -eq 0 ]; then
                    /usr/bin/printf '%s' "$rollback_current" | /usr/bin/plutil -lint -s - >/dev/null 2>&1 || restore_failed=1
                fi
                if [ "$restore_failed" -eq 0 ]; then
                    actual_value=$(extract_key "$rollback_current" \(Self.shellQuote(interface.key)))
                    desired_value=$(extract_key "$desired" \(Self.shellQuote(interface.key)))
                    original_value=$(extract_key "$original" \(Self.shellQuote(interface.key)))
                    if [ "$actual_value" = "$desired_value" ] || [ "$actual_value" = "$original_value" ]; then
                        \(try Self.writeCommand(interface, values: baseline.configuration[interface])) || restore_failed=1
                        restored=$(\(Self.readCommand)) || restore_failed=1
                        restored_value=$(extract_key "$restored" \(Self.shellQuote(interface.key)))
                        [ "$restored_value" = "$original_value" ] || restore_failed=1
                    else
                        restore_failed=1
                    fi
                fi
                if [ "$restore_failed" -ne 0 ]; then rollback_failed=1; fi
            fi
            """
        }.joined(separator: "\n")
        let writes = try changes.map { "touched_\($0.rawValue)=1\n" + (try Self.writeCommand($0, values: desired[$0])) + " || fail_and_restore" }
            .joined(separator: "\n")
        let verifications = changes.map { interface in
            "verify_key \(Self.shellQuote(interface.key)) || fail_and_restore"
        }.joined(separator: "\n")

        return """
        set -eu
        original=\(Self.shellQuote(baseline.xml))
        desired=\(Self.shellQuote(desiredXML))
        current=$(\(Self.readCommand)) || { echo HALLPASS_READ_FAILED >&2; exit 20; }
        if [ "$current" != "$original" ]; then
            echo HALLPASS_CONFLICT >&2
            exit 21
        fi
        rollback_failed=0
        touched_wifi=0
        touched_ethernet=0
        extract_key() {
            if extracted=$(/usr/bin/printf '%s' "$1" | /usr/bin/plutil -extract "$2" xml1 -o - - 2>/dev/null); then
                /usr/bin/printf '%s' "$extracted"
            else
                /usr/bin/printf '%s' HALLPASS_MISSING_KEY
            fi
        }
        fail_and_restore() {
            \(rollback)
            if [ "$rollback_failed" -ne 0 ]; then
                echo HALLPASS_ROLLBACK_FAILED >&2
                exit 23
            fi
            echo HALLPASS_WRITE_FAILED_RESTORED >&2
            exit 22
        }
        verify_key() {
            key="$1"
            actual=$(\(Self.readCommand)) || return 1
            /usr/bin/printf '%s' "$actual" | /usr/bin/plutil -lint -s - >/dev/null 2>&1 || return 1
            actual_value=$(extract_key "$actual" "$key")
            wanted_value=$(extract_key "$desired" "$key")
            [ "$actual_value" = "$wanted_value" ]
        }
        \(writes)
        \(verifications)
        final=$(\(Self.readCommand)) || fail_and_restore
        /usr/bin/printf '%s\\n' "$final"
        """
    }

    private static func writeCommand(_ interface: NetworkInterface, values: [String]?) throws -> String {
        let target = shellQuote(domain)
        let key = shellQuote(interface.key)
        guard let values else {
            // A missing key already has the intended state. Do not hide actual delete errors.
            return "if /usr/bin/defaults read \(target) \(key) >/dev/null 2>&1; then /usr/bin/defaults delete \(target) \(key); fi"
        }
        // Pass a typed XML array, not -array elements that defaults may reinterpret
        // as OpenStep property lists. This also restores unusual pre-existing strings.
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        return "/usr/bin/defaults write \(target) \(key) " + shellQuote(String(decoding: data, as: UTF8.self))
    }
}
