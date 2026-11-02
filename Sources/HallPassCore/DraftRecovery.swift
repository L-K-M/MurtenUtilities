import Foundation

/// Recovery retains the original baseline so restoring cannot bypass conflict detection.
public struct DraftRecovery: Codable, Sendable {
    public static let maximumDataSize = 4_194_304
    private static let currentVersion = 1

    private let formatVersion: Int
    private let baselineXML: String
    public let draft: NetworkConfiguration

    public var baseline: PreferencesSnapshot {
        get throws { try PreferencesSnapshot(xml: baselineXML) }
    }

    public init(baseline: PreferencesSnapshot, draft: NetworkConfiguration) {
        formatVersion = Self.currentVersion
        baselineXML = baseline.xml
        self.draft = draft
    }

    public func encoded() throws -> Data {
        let data = try JSONEncoder().encode(self)
        guard data.count <= Self.maximumDataSize else { throw ConfigurationError.unsupportedBackup }
        return data
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumDataSize else { throw ConfigurationError.unsupportedBackup }
        let recovery = try JSONDecoder().decode(Self.self, from: data)
        guard recovery.formatVersion == currentVersion else { throw ConfigurationError.unsupportedBackup }
        guard (try? recovery.baseline) != nil else { throw ConfigurationError.invalidPropertyList }
        return recovery
    }
}
