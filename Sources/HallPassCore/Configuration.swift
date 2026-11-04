import Foundation

public enum NetworkInterface: String, CaseIterable, Codable, Sendable, Identifiable {
    case wifi, ethernet
    public var id: String { rawValue }
    public var title: String { self == .wifi ? "Wi-Fi" : "Ethernet" }
    public var symbol: String { self == .wifi ? "wifi" : "cable.connector" }
    public var key: String {
        self == .wifi ? "AllowedWiFiLocalNetworkAddresses" : "AllowedEthernetLocalNetworkAddresses"
    }
}

public struct NetworkConfiguration: Codable, Equatable, Sendable {
    public static let maximumNetworksPerInterface = 512

    public var wifi: [String]?
    public var ethernet: [String]?

    public init(wifi: [String]? = nil, ethernet: [String]? = nil) {
        self.wifi = wifi
        self.ethernet = ethernet
    }

    public subscript(_ interface: NetworkInterface) -> [String]? {
        get { interface == .wifi ? wifi : ethernet }
        set {
            if interface == .wifi { wifi = newValue } else { ethernet = newValue }
        }
    }

    public var propertyList: [String: Any] {
        var values: [String: Any] = [:]
        for interface in NetworkInterface.allCases {
            if let networks = self[interface] { values[interface.key] = networks }
        }
        return values
    }

    public func validate() throws {
        for interface in NetworkInterface.allCases {
            guard let networks = self[interface] else { continue }
            guard networks.count <= Self.maximumNetworksPerInterface else { throw ConfigurationError.tooManyNetworks }
            for network in networks { _ = try CIDR(network) }
        }
    }

    public static let example = NetworkConfiguration(
        wifi: ["169.254.0.0/16", "192.168.1.0/24"], ethernet: ["169.254.0.0/16"]
    )
}

public enum ConfigurationError: LocalizedError {
    case invalidPropertyList, invalidKey(String), tooManyNetworks, unsupportedBackup, duplicateNetwork, invalidSelection
    public var errorDescription: String? {
        switch self {
        case .invalidPropertyList: "The system settings could not be read as a valid property list."
        case .invalidKey(let key): "The setting \(key) does not contain an array of strings. Local Network Access does not change this configuration."
        case .tooManyNetworks: "Each connection allows at most \(NetworkConfiguration.maximumNetworksPerInterface) network ranges."
        case .unsupportedBackup: "This backup has an unknown format."
        case .duplicateNetwork: "This IP range already exists for the selected connection."
        case .invalidSelection: "The selected IP range no longer exists."
        }
    }
}

public struct PreferencesSnapshot: Sendable {
    public let xml: String
    public let configuration: NetworkConfiguration

    public init(xml: String) throws {
        guard let data = xml.data(using: .utf8),
              let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw ConfigurationError.invalidPropertyList }
        var configuration = NetworkConfiguration()
        for interface in NetworkInterface.allCases {
            if let value = dictionary[interface.key] {
                guard let strings = value as? [String] else { throw ConfigurationError.invalidKey(interface.key) }
                configuration[interface] = strings
            }
        }
        self.xml = xml.trimmingCharacters(in: .newlines)
        self.configuration = configuration
    }

    public init(configuration: NetworkConfiguration) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: configuration.propertyList, format: .xml, options: 0)
        try self.init(xml: String(decoding: data, as: UTF8.self))
    }
}

public struct ConfigurationBackup: Codable, Sendable {
    public static let maximumDataSize = 1_048_576
    private static let currentVersion = 1

    public let formatVersion: Int
    public let createdAt: Date
    public let configuration: NetworkConfiguration

    public init(configuration: NetworkConfiguration) {
        self.formatVersion = Self.currentVersion
        self.createdAt = Date()
        self.configuration = configuration
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumDataSize else { throw ConfigurationError.unsupportedBackup }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(Self.self, from: data)
        guard backup.formatVersion == currentVersion else { throw ConfigurationError.unsupportedBackup }
        // Keep legacy values inspectable. The draft is validated again before saving.
        return backup
    }
}
