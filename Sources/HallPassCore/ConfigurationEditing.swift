import Foundation

extension NetworkConfiguration {
    public func adding(_ notation: String, to interfaces: [NetworkInterface]) throws -> Self {
        let canonical = try CIDR(notation).notation
        var result = self

        for interface in interfaces {
            var values = result[interface] ?? []
            guard !values.contains(where: { (try? CIDR($0).notation) == canonical }) else { continue }
            guard values.count < Self.maximumNetworksPerInterface else { throw ConfigurationError.tooManyNetworks }
            values.append(canonical)
            result[interface] = values
        }

        return result
    }

    public func removing(_ indices: Set<Int>, from interface: NetworkInterface) -> Self {
        guard let values = self[interface], values.indices.contains(where: indices.contains) else { return self }
        var result = self
        let remaining = values.enumerated().filter { !indices.contains($0.offset) }.map(\.element)
        result[interface] = remaining.isEmpty ? nil : remaining
        return result
    }

    public func replacing(_ index: Int, with notation: String, in interface: NetworkInterface) throws -> Self {
        guard var values = self[interface], values.indices.contains(index) else { throw ConfigurationError.invalidSelection }
        let canonical = try CIDR(notation).notation
        let duplicate = values.enumerated().contains { $0.offset != index && (try? CIDR($0.element).notation) == canonical }
        guard !duplicate else { throw ConfigurationError.duplicateNetwork }

        values[index] = canonical
        var result = self
        result[interface] = values
        return result
    }

    public func changes(from baseline: Self) -> [InterfaceChange] {
        NetworkInterface.allCases.compactMap { interface in
            guard baseline[interface] != self[interface] else { return nil }
            return InterfaceChange(
                interface: interface,
                added: Self.unmatched(self[interface] ?? [], against: baseline[interface] ?? []),
                removed: Self.unmatched(baseline[interface] ?? [], against: self[interface] ?? [])
            )
        }
    }

    // Count occurrences so removing one duplicate is still visible in the review.
    private static func unmatched(_ values: [String], against other: [String]) -> [String] {
        var counts = other.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return values.filter { value in
            guard counts[value, default: 0] > 0 else { return true }
            counts[value, default: 0] -= 1
            return false
        }
    }
}

public struct InterfaceChange: Identifiable, Sendable {
    public var id: NetworkInterface { interface }
    public let interface: NetworkInterface
    public let added: [String]
    public let removed: [String]
}
