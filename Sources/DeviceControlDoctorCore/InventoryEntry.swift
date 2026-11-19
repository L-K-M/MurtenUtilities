import Foundation

/// One permission record in the inventory, with the flags that explain it.
public struct InventoryEntry: Identifiable, Hashable, Sendable {
    public struct Flags: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// The app is no longer on this Mac, or only in the Trash.
        public static let leftover = Flags(rawValue: 1 << 0)
        /// Another client with a different identifier has the same name.
        public static let lookAlike = Flags(rawValue: 1 << 1)
        /// The app no longer satisfies the requirement recorded with the decision.
        public static let broken = Flags(rawValue: 1 << 2)
        /// A granted high-risk service.
        public static let highRisk = Flags(rawValue: 1 << 3)
        /// Part of macOS.
        public static let system = Flags(rawValue: 1 << 4)
        /// Set by device management.
        public static let managed = Flags(rawValue: 1 << 5)
        /// The app is on a disk that is not connected.
        public static let offline = Flags(rawValue: 1 << 6)
        /// An Automation entry whose controlled app is gone.
        public static let missingTarget = Flags(rawValue: 1 << 7)
    }

    public let record: PermissionRecord
    public let service: PrivacyService
    public let client: ClientStatus
    public let signature: SignatureCheck
    public let target: ClientStatus?
    public let flags: Flags

    public init(record: PermissionRecord, service: PrivacyService, client: ClientStatus,
                signature: SignatureCheck, target: ClientStatus?, flags: Flags) {
        self.record = record
        self.service = service
        self.client = client
        self.signature = signature
        self.target = target
        self.flags = flags
    }

    public var id: String { record.key }

    /// Entries of the same client share it, whichever database holds them.
    public var clientKey: String { (record.clientKind == .path ? "path:" : "bundle:") + record.client }

    /// Whether `tccutil` can reset it: it needs a bundle identifier, and
    /// the module never touches macOS's own or managed decisions.
    public var canReset: Bool {
        record.clientKind == .bundleIdentifier
            && ClientIdentifier.isBundleIdentifier(record.client)
            && !flags.contains(.system)
            && !flags.contains(.managed)
    }

    /// The flags in display order, with a short title each.
    public var flagTitles: [String] {
        Self.flagOrder.compactMap { flags.contains($0.flag) ? $0.title : nil }
    }

    static let flagOrder: [(flag: Flags, title: String)] = [
        (.leftover, "Leftover"), (.lookAlike, "Look-alike"), (.broken, "Broken"), (.highRisk, "High-risk"),
        (.offline, "Disk not connected"), (.missingTarget, "Target gone"), (.managed, "Managed"), (.system, "macOS"),
    ]

    /// What each flag means, for the detail view and the report.
    public static func explanation(of flag: Flags) -> String {
        switch flag {
        case .leftover: return "The app is no longer on this Mac, or is only in the Trash."
        case .lookAlike: return "Another app with the same name has a different identifier."
        case .broken: return "The app changed since it got this permission, so the decision no longer matches it. This can happen after an update."
        case .highRisk: return "This permission can read all your files, control your Mac, record your screen, or watch your typing."
        case .offline: return "The app is on a disk that is not connected."
        case .missingTarget: return "The app this entry may control is no longer on this Mac."
        case .managed: return "Set by your organization through device management. App Permission Checkup does not change it."
        case .system: return "Part of macOS. App Permission Checkup does not change it."
        default: return ""
        }
    }
}
