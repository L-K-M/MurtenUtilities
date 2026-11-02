import Foundation
import Testing
@testable import HallPassCore

/// The suite's UI is English (PLAN.md, Decisions so far); core messages
/// reach the pane verbatim, so they are pinned here.
struct EnglishMessagesTests {
    @Test func interfaceTitlesAreEnglish() {
        #expect(NetworkInterface.wifi.title == "Wi-Fi")
        #expect(NetworkInterface.ethernet.title == "Ethernet")
    }

    @Test func cidrErrorsAreEnglish() {
        #expect(throws: CIDRError.invalidFormat("Exactly one slash is required.")) { try CIDR("192.168.1.0") }
        #expect(throws: CIDRError.invalidPrefix("The IPv4 prefix length must be between 0 and 32.")) {
            try CIDR("192.168.1.0/33")
        }
    }

    @Test func configurationErrorsAreEnglish() {
        #expect(ConfigurationError.tooManyNetworks.errorDescription == "Each connection allows at most 512 network ranges.")
        #expect(ConfigurationError.unsupportedBackup.errorDescription == "This backup has an unknown format.")
    }
}
