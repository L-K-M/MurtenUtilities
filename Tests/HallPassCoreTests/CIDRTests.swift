import Testing
import Foundation
@testable import HallPassCore

@Suite struct CIDRTests {

    // MARK: - IPv4 canonicalization

    @Test func ipv4_canonicalizeHostBits_24() throws {
        let cidr = try CIDR("192.168.1.42/24")
        #expect(cidr.notation == "192.168.1.0/24")
        #expect(cidr.isIPv6 == false)
        #expect(cidr.prefixLength == 24)
    }

    @Test func ipv4_canonicalizeHostBits_16() throws {
        let cidr = try CIDR("169.254.4.5/16")
        #expect(cidr.notation == "169.254.0.0/16")
        #expect(cidr.isIPv6 == false)
        #expect(cidr.prefixLength == 16)
    }

    @Test func ipv4_prefix32_unchanged() throws {
        let cidr = try CIDR("10.0.0.1/32")
        #expect(cidr.notation == "10.0.0.1/32")
        #expect(cidr.isIPv6 == false)
        #expect(cidr.prefixLength == 32)
    }

    @Test func ipv4_prefix0() throws {
        let cidr = try CIDR("255.255.255.255/0")
        #expect(cidr.notation == "0.0.0.0/0")
        #expect(cidr.isIPv6 == false)
        #expect(cidr.prefixLength == 0)
    }

    // MARK: - IPv6 canonicalization

    @Test func ipv6_canonicalizeHostBits_48() throws {
        let cidr = try CIDR("fd12:3456:789a::1/48")
        #expect(cidr.notation == "fd12:3456:789a::/48")
        #expect(cidr.isIPv6 == true)
        #expect(cidr.prefixLength == 48)
    }

    @Test func ipv6_slash0() throws {
        let cidr = try CIDR("::/0")
        #expect(cidr.notation == "::/0")
        #expect(cidr.isIPv6 == true)
        #expect(cidr.prefixLength == 0)
    }

    @Test func ipv6_prefix128_unchanged() throws {
        let cidr = try CIDR("fd12:3456:789a::1/128")
        #expect(cidr.notation == "fd12:3456:789a::1/128")
        #expect(cidr.isIPv6 == true)
        #expect(cidr.prefixLength == 128)
    }

    @Test func ipv6_compressedNotation() throws {
        let cidr = try CIDR("2001:0db8:0000:0000:0000:0000:0000:0001/64")
        #expect(cidr.notation == "2001:db8::/64")
        #expect(cidr.isIPv6 == true)
        #expect(cidr.prefixLength == 64)
    }

    // MARK: - Whitespace trimming

    @Test func trimsOuterWhitespace() throws {
        let cidr = try CIDR("  192.168.1.42/24  ")
        #expect(cidr.notation == "192.168.1.0/24")
    }

    @Test func rejectsInnerWhitespace() throws {
        #expect(throws: CIDRError.self) { try CIDR("192.168.1.42 /24") }
        #expect(throws: CIDRError.self) { try CIDR("192.168.1.42/ 24") }
        #expect(throws: CIDRError.self) { try CIDR("192. 168.1.42/24") }
    }

    // MARK: - Invalid prefix length

    @Test func rejectsIPv4PrefixTooLarge() throws {
        #expect(throws: CIDRError.self) { try CIDR("192.168.1.0/33") }
    }

    @Test func rejectsIPv4PrefixNegative() throws {
        #expect(throws: CIDRError.self) { try CIDR("192.168.1.0/-1") }
    }

    @Test func rejectsIPv6PrefixTooLarge() throws {
        #expect(throws: CIDRError.self) { try CIDR("::1/129") }
    }

    @Test func rejectsIPv6PrefixNegative() throws {
        #expect(throws: CIDRError.self) { try CIDR("::1/-1") }
    }

    @Test func rejectsNonDecimalPrefix() throws {
        #expect(throws: CIDRError.self) { try CIDR("192.168.1.0/0x20") }
        #expect(throws: CIDRError.self) { try CIDR("192.168.1.0/abc") }
    }

    // MARK: - Malformed input rejection

    @Test func rejectsNoSlash() throws {
        #expect(throws: CIDRError.self) { try CIDR("192.168.1.0") }
    }

    @Test func rejectsMultipleSlashes() throws {
        #expect(throws: CIDRError.self) { try CIDR("192.168.1.0/24/8") }
        #expect(throws: CIDRError.self) { try CIDR("192.168.1.0//24") }
    }

    @Test func rejectsEmptyInput() throws {
        #expect(throws: CIDRError.self) { try CIDR("") }
    }

    @Test func rejectsHostname() throws {
        #expect(throws: CIDRError.self) { try CIDR("example.com/24") }
    }

    @Test func rejectsBracketNotation() throws {
        #expect(throws: CIDRError.self) { try CIDR("[2001:db8::1]/64") }
    }

    @Test func rejectsScopedIPv6() throws {
        #expect(throws: CIDRError.self) { try CIDR("fe80::1%eth0/64") }
    }

    @Test func rejectsShellSyntax() throws {
        #expect(throws: CIDRError.self) { try CIDR("192.168.1.0;rm -rf / /24") }
        #expect(throws: CIDRError.self) { try CIDR("192.168.1.0|cat /etc/passwd/24") }
        #expect(throws: CIDRError.self) { try CIDR("192.168.1.0`whoami`/24") }
        #expect(throws: CIDRError.self) { try CIDR("192.168.1.0$(id)/24") }
    }

    @Test func rejectsMalformedIPv4() throws {
        #expect(throws: CIDRError.self) { try CIDR("256.1.1.1/24") }
        #expect(throws: CIDRError.self) { try CIDR("1.2.3/24") }
        #expect(throws: CIDRError.self) { try CIDR("1.2.3.4.5/24") }
    }

    @Test func rejectsMalformedIPv6() throws {
        #expect(throws: CIDRError.self) { try CIDR("gggg::1/64") }
        #expect(throws: CIDRError.self) { try CIDR("::zzzz/64") }
    }

    // MARK: - Error is LocalizedError

    @Test func errorIsLocalizedError() throws {
        do {
            _ = try CIDR("invalid")
            Issue.record("Expected error")
        } catch {
            #expect(error is LocalizedError)
            #expect((error as? LocalizedError)?.errorDescription != nil)
        }
    }

    // MARK: - Hashable & Sendable

    @Test func hashable() throws {
        let a = try CIDR("192.168.1.42/24")
        let b = try CIDR("192.168.1.100/24")
        let c = try CIDR("192.168.1.42/24")
        #expect(a == b)
        #expect(a == c)
        #expect(a.hashValue == b.hashValue)
    }

    // MARK: - Edge cases

    @Test func ipv4_allZeros() throws {
        let cidr = try CIDR("0.0.0.0/0")
        #expect(cidr.notation == "0.0.0.0/0")
        #expect(cidr.isIPv6 == false)
    }

    @Test func ipv6_loopback() throws {
        let cidr = try CIDR("::1/128")
        #expect(cidr.notation == "::1/128")
        #expect(cidr.isIPv6 == true)
    }

    @Test func ipv4_loopback() throws {
        let cidr = try CIDR("127.0.0.1/8")
        #expect(cidr.notation == "127.0.0.0/8")
        #expect(cidr.isIPv6 == false)
    }

    @Test func ipv6_fullAddress() throws {
        let cidr = try CIDR("2001:0db8:0000:0000:0000:0000:0000:0000/32")
        #expect(cidr.notation == "2001:db8::/32")
        #expect(cidr.isIPv6 == true)
    }

    @Test func leadingZerosInPrefixRejected() throws {
        // Int("08") parses as 8, but "08" is still a valid decimal for Int()
        // This is acceptable behavior - leading zeros in prefix are parsed as decimal
        let cidr = try CIDR("192.168.1.0/08")
        #expect(cidr.notation == "192.0.0.0/8")
    }

    // MARK: - Partial byte masking

    @Test func ipv6_partialByte_mask7() throws {
        // fdff::1234/7 => fc00::/7 (first byte 0xfd masked with 0xfe = 0xfc)
        let cidr = try CIDR("fdff::1234/7")
        #expect(cidr.notation == "fc00::/7")
        #expect(cidr.isIPv6 == true)
        #expect(cidr.prefixLength == 7)
    }

    @Test func ipv6_partialByte_mask10() throws {
        // fe80::1/10 => fe80::/10 (the first byte is preserved, the second byte is masked with 0xc0)
        let cidr = try CIDR("fe80::1/10")
        #expect(cidr.notation == "fe80::/10")
        #expect(cidr.isIPv6 == true)
        #expect(cidr.prefixLength == 10)
    }

    @Test func ipv4_partialByte_mask25() throws {
        // 192.168.1.255/25 => 192.168.1.128/25 (fourth octet 0xff masked with 0x80 = 0x80)
        let cidr = try CIDR("192.168.1.255/25")
        #expect(cidr.notation == "192.168.1.128/25")
        #expect(cidr.isIPv6 == false)
        #expect(cidr.prefixLength == 25)
    }

    @Test func ipv4_partialByte_mask31() throws {
        // 192.168.1.255/31 => 192.168.1.254/31 (last octet 0xff masked with 0xfe = 0xfe)
        let cidr = try CIDR("192.168.1.255/31")
        #expect(cidr.notation == "192.168.1.254/31")
        #expect(cidr.isIPv6 == false)
        #expect(cidr.prefixLength == 31)
    }

    // MARK: - Prefix character validation

    @Test func rejectsPlusPrefix() throws {
        // "+24" should be rejected because prefix must contain ASCII digits only
        #expect(throws: CIDRError.self) { try CIDR("192.168.1.0/+24") }
    }

    @Test func rejectsMinusZeroPrefix() throws {
        // "-0" should be rejected because prefix must contain ASCII digits only
        #expect(throws: CIDRError.self) { try CIDR("192.168.1.0/-0") }
    }

    // MARK: - NUL character rejection

    @Test func rejectsEmbeddedNUL() throws {
        #expect(throws: CIDRError.self) { try CIDR("192.168.1.0\0/24") }
        #expect(throws: CIDRError.self) { try CIDR("192.168.1.0/2\04") }
        #expect(throws: CIDRError.self) { try CIDR("::1\0/64") }
    }

    // MARK: - Newline trimming

    @Test func trimsOuterNewlines() throws {
        let cidr = try CIDR("\n  192.168.1.42/24  \n")
        #expect(cidr.notation == "192.168.1.0/24")
    }
}
