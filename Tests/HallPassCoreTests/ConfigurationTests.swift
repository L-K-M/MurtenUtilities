import Foundation
import Testing
@testable import HallPassCore

struct ConfigurationTests {
    @Test func preservesMissingVersusEmpty() throws {
        let snapshot = try PreferencesSnapshot(configuration: .init(wifi: [], ethernet: nil))
        #expect(snapshot.configuration.wifi == [])
        #expect(snapshot.configuration.ethernet == nil)
    }

    @Test func rejectsUnexpectedPreferenceType() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: [NetworkInterface.wifi.key: "not an array"], format: .xml, options: 0
        )
        #expect(throws: ConfigurationError.self) {
            try PreferencesSnapshot(xml: String(decoding: data, as: UTF8.self))
        }
    }

    @Test func backupRoundTripAndRejectsUnknownVersion() throws {
        let configuration = NetworkConfiguration(wifi: [], ethernet: ["fe80::/10"])
        let data = try ConfigurationBackup(configuration: configuration).encoded()
        #expect(try ConfigurationBackup.decode(data).configuration == configuration)
        let altered = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\"formatVersion\" : 1", with: "\"formatVersion\" : 99")
        #expect(throws: ConfigurationError.self) { try ConfigurationBackup.decode(Data(altered.utf8)) }
    }

    @Test func backupCanReopenLegacyValuesForInspection() throws {
        let configuration = NetworkConfiguration(wifi: ["legacy-invalid-value"], ethernet: nil)
        let data = try ConfigurationBackup(configuration: configuration).encoded()
        #expect(try ConfigurationBackup.decode(data).configuration == configuration)
        #expect(throws: CIDRError.self) { try configuration.validate() }
    }
}
