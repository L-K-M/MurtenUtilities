import Foundation
import Testing
@testable import HallPassCore

struct DraftTests {
    @Test func addsCanonicalRangesWithoutRewritingExistingValues() throws {
        let original = NetworkConfiguration(wifi: ["192.168.1.42/24", "old-value"], ethernet: [])
        let result = try original.adding("192.168.1.99/24", to: NetworkInterface.allCases)
        #expect(result.wifi == original.wifi)
        #expect(result.ethernet == ["192.168.1.0/24"])
    }

    @Test func addingToBothInterfacesIsAtomicAtTheLimit() throws {
        let original = NetworkConfiguration(
            wifi: ["169.254.0.0/16"],
            ethernet: (0..<NetworkConfiguration.maximumNetworksPerInterface).map { "10.0.\($0 / 256).\($0 % 256)/32" }
        )
        #expect(throws: ConfigurationError.self) {
            try original.adding("192.168.1.0/24", to: NetworkInterface.allCases)
        }
        #expect(original.wifi == ["169.254.0.0/16"])
    }

    @Test func removesOnlySelectedOccurrencesAndKeepsOtherInterfaces() {
        let original = NetworkConfiguration(wifi: ["old", "old", "fe80::/10"], ethernet: [])
        let result = original.removing([0], from: .wifi)
        #expect(result.wifi == ["old", "fe80::/10"])
        #expect(result.ethernet == [])
        #expect(original.removing([], from: .ethernet) == original)
        #expect(result.removing([0, 1], from: .wifi).wifi == nil)
    }

    @Test func replacesOneLegacyValueInPlace() throws {
        let original = NetworkConfiguration(wifi: ["old", "fe80::/10"], ethernet: ["untouched"])
        let result = try original.replacing(0, with: "192.168.1.42/24", in: .wifi)
        #expect(result.wifi == ["192.168.1.0/24", "fe80::/10"])
        #expect(result.ethernet == original.ethernet)
        #expect(throws: ConfigurationError.self) { try result.replacing(0, with: "fe80::/10", in: .wifi) }
        #expect(throws: ConfigurationError.self) { try result.replacing(99, with: "::/0", in: .wifi) }
    }

    @Test func reviewCountsDuplicateAdditionsAndRemovals() {
        let before = NetworkConfiguration(wifi: ["old", "old", "fe80::/10"])
        let after = NetworkConfiguration(wifi: ["old", "fe80::/10", "fe80::/10"])
        let changes = after.changes(from: before)
        #expect(changes.count == 1)
        #expect(changes.first?.added == ["fe80::/10"])
        #expect(changes.first?.removed == ["old"])
    }

    @Test func reviewRetainsMissingVersusEmptyAndOrderingChanges() {
        let before = NetworkConfiguration(wifi: nil, ethernet: ["one", "two"])
        let after = NetworkConfiguration(wifi: [], ethernet: ["two", "one"])
        let changes = after.changes(from: before)
        #expect(changes.map(\.interface) == [.wifi, .ethernet])
        #expect(changes.allSatisfy { $0.added.isEmpty && $0.removed.isEmpty })
    }

    @Test func recoveryPreservesBaselineAndAnUnvalidatedDraft() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["Unmanaged": "preserve", NetworkInterface.wifi.key: [String]()],
            format: .xml, options: 0
        )
        let baseline = try PreferencesSnapshot(xml: String(decoding: data, as: UTF8.self))
        let draft = NetworkConfiguration(wifi: ["legacy", "legacy"], ethernet: [])
        let recovery = try DraftRecovery.decode(DraftRecovery(baseline: baseline, draft: draft).encoded())
        #expect(try recovery.baseline.xml == baseline.xml)
        #expect(try recovery.baseline.configuration.wifi == [])
        #expect(try recovery.baseline.configuration.ethernet == nil)
        #expect(recovery.draft == draft)
    }

    @Test func recoveryRejectsUnknownVersionsAndInvalidBaselines() throws {
        let baseline = try PreferencesSnapshot(configuration: .example)
        let data = try DraftRecovery(baseline: baseline, draft: .init()).encoded()
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["formatVersion"] = 99
        #expect(throws: ConfigurationError.self) { try DraftRecovery.decode(JSONSerialization.data(withJSONObject: json)) }
        json["formatVersion"] = 1
        json["baselineXML"] = "not a plist"
        #expect(throws: ConfigurationError.self) { try DraftRecovery.decode(JSONSerialization.data(withJSONObject: json)) }
    }

    @Test func existingBackupSchemaRoundTripsWithoutNormalizingData() throws {
        let json = #"{"formatVersion":1,"createdAt":"2024-09-01T12:00:00Z","configuration":{"wifi":[],"ethernet":["192.168.1.42/24","legacy","legacy"]}}"#
        let backup = try ConfigurationBackup.decode(Data(json.utf8))
        let roundTrip = try ConfigurationBackup.decode(backup.encoded())
        #expect(roundTrip.createdAt == backup.createdAt)
        #expect(roundTrip.configuration == backup.configuration)
        #expect(roundTrip.configuration.ethernet == ["192.168.1.42/24", "legacy", "legacy"])
    }
}
