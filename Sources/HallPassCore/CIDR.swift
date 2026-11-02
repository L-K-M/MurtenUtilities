import Foundation
import Darwin

/// Represents an IPv4 or IPv6 CIDR network in canonical (compressed) form.
public struct CIDR: Hashable, Sendable {
    /// The canonical CIDR notation string (e.g., "192.168.1.0/24", "fd12:3456:789a::/48").
    public let notation: String

    /// Whether this is an IPv6 address (false for IPv4).
    public let isIPv6: Bool

    /// The prefix length (0–32 for IPv4, 0–128 for IPv6).
    public let prefixLength: Int

    /// Parses a CIDR notation string and returns a canonical ``CIDR`` value.
    ///
    /// - Parameter input: The raw CIDR string (e.g., "192.168.1.42/24").
    /// - Throws: A ``CIDRError`` with an English explanation if the input is invalid.
    public init(_ input: String) throws {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Must contain exactly one slash
        let slashCount = trimmed.filter { $0 == "/" }.count
        guard slashCount == 1 else {
            throw CIDRError.invalidFormat("Exactly one slash is required.")
        }

        let components = trimmed.split(separator: "/", maxSplits: 1)
        guard components.count == 2 else {
            throw CIDRError.invalidFormat("Exactly one slash is required.")
        }

        let hostPart = String(components[0])
        let prefixPart = String(components[1])

        // Reject inner whitespace in host or prefix
        if hostPart.contains(where: { $0.isWhitespace }) || prefixPart.contains(where: { $0.isWhitespace }) {
            throw CIDRError.invalidFormat("Spaces are not allowed inside the notation.")
        }

        // Reject embedded NUL characters
        if hostPart.contains("\0") || prefixPart.contains("\0") {
            throw CIDRError.invalidFormat("Embedded NUL characters are not allowed.")
        }

        // Prefix must contain ASCII digits only (reject +, -, and other characters)
        guard !prefixPart.isEmpty, prefixPart.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw CIDRError.invalidPrefix("The prefix length must be a decimal number.")
        }
        guard let prefixLength = Int(prefixPart) else {
            throw CIDRError.invalidPrefix("The prefix length must be a decimal number.")
        }

        // Reject non-ASCII characters in host part before passing to inet_pton
        // Allow only ASCII hex digits, colon, and period
        let allowedHostChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF:.")
        if hostPart.rangeOfCharacter(from: allowedHostChars.inverted) != nil {
            throw CIDRError.invalidFormat("The address contains invalid characters.")
        }

        // Detect IPv4 vs IPv6
        let isIPv6 = hostPart.contains(":")
        let isIPv4 = !isIPv6

        // Reject bracket notation
        if hostPart.contains("[") || hostPart.contains("]") {
            throw CIDRError.invalidFormat("Bracket notation is not allowed.")
        }

        // Reject scoped IPv6 zone IDs
        if hostPart.contains("%") {
            throw CIDRError.invalidFormat("IPv6 zone IDs (scope IDs) are not allowed.")
        }

        // Reject shell syntax characters
        let shellChars = Set<Character>(";|&`$(){}!#~<>")
        if hostPart.contains(where: { shellChars.contains($0) }) {
            throw CIDRError.invalidFormat("Shell syntax characters are not allowed.")
        }
        if prefixPart.contains(where: { shellChars.contains($0) }) {
            throw CIDRError.invalidPrefix("Shell syntax characters are not allowed.")
        }

        // Reject hostnames (letters in IPv4 context)
        if isIPv4 && hostPart.rangeOfCharacter(from: .letters) != nil {
            throw CIDRError.invalidFormat("Hostnames are not allowed.")
        }

        // Parse the address using inet_pton
        var parsedAddress: Data?
        if isIPv6 {
            var addr6 = in6_addr()
            let result = inet_pton(AF_INET6, (hostPart as NSString).utf8String, &addr6)
            if result != 1 {
                throw CIDRError.invalidFormat("Invalid IPv6 address: \"\(hostPart)\".")
            }
            // Validate prefix range for IPv6
            guard prefixLength >= 0 && prefixLength <= 128 else {
                throw CIDRError.invalidPrefix("The IPv6 prefix length must be between 0 and 128.")
            }
            // Convert in6_addr to Data
            var bytes = [UInt8](repeating: 0, count: MemoryLayout<in6_addr>.size)
            memcpy(&bytes, &addr6, MemoryLayout<in6_addr>.size)
            parsedAddress = Data(bytes)
        } else {
            var addr4 = in_addr()
            let result = inet_pton(AF_INET, (hostPart as NSString).utf8String, &addr4)
            if result != 1 {
                throw CIDRError.invalidFormat("Invalid IPv4 address: \"\(hostPart)\".")
            }
            // Validate prefix range for IPv4
            guard prefixLength >= 0 && prefixLength <= 32 else {
                throw CIDRError.invalidPrefix("The IPv4 prefix length must be between 0 and 32.")
            }
            // Convert in_addr to Data
            var bytes = [UInt8](repeating: 0, count: MemoryLayout<in_addr>.size)
            memcpy(&bytes, &addr4, MemoryLayout<in_addr>.size)
            parsedAddress = Data(bytes)
        }

        // Apply network mask: zero out host bits
        let addressBytes = parsedAddress!
        let networkBytes = CIDR.applyMask(addressBytes, prefixLength: prefixLength)

        // Convert back to canonical string using inet_ntop
        let canonicalHost: String
        if isIPv6 {
            var addr6 = in6_addr()
            memcpy(&addr6, networkBytes, MemoryLayout<in6_addr>.size)
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            if let ptr = inet_ntop(AF_INET6, &addr6, &buffer, socklen_t(buffer.count)) {
                canonicalHost = String(cString: ptr)
            } else {
                throw CIDRError.invalidFormat("Could not convert the IPv6 address.")
            }
        } else {
            var addr4 = in_addr()
            memcpy(&addr4, networkBytes, MemoryLayout<in_addr>.size)
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            if let ptr = inet_ntop(AF_INET, &addr4, &buffer, socklen_t(buffer.count)) {
                canonicalHost = String(cString: ptr)
            } else {
                throw CIDRError.invalidFormat("Could not convert the IPv4 address.")
            }
        }

        self.notation = "\(canonicalHost)/\(prefixLength)"
        self.isIPv6 = isIPv6
        self.prefixLength = prefixLength
    }

    /// Applies a CIDR prefix mask to the given address bytes, zeroing out host bits.
    private static func applyMask(_ bytes: Data, prefixLength: Int) -> [UInt8] {
        var result = [UInt8](bytes)
        for index in result.indices {
            let bitsToKeep = max(0, min(8, prefixLength - index * 8))
            if bitsToKeep == 0 {
                result[index] = 0
            } else if bitsToKeep < 8 {
                result[index] &= UInt8.max << (8 - bitsToKeep)
            }
        }

        return result
    }
}

/// Errors thrown by ``CIDR`` initialization.
public enum CIDRError: LocalizedError, Hashable {
    case invalidFormat(String)
    case invalidPrefix(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFormat(let msg):
            return msg
        case .invalidPrefix(let msg):
            return msg
        }
    }
}
