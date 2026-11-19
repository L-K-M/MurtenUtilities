import Foundation

/// One privacy (TCC) service as the permission inventory shows it.
///
/// Identifiers, titles and Settings anchors were checked against macOS
/// 27.0.1: the TCC framework's prompts, the Privacy & Security settings
/// extension's `TCCServiceList.plist`, its English titles and the anchors
/// its binary names. A service missing from `known` (a newer macOS, a
/// private service) still appears, under a title derived from its
/// identifier and with the Privacy & Security page as its Settings link.
public struct PrivacyService: Hashable, Identifiable, Sendable {
    public enum Risk: Sendable {
        /// Reads every file, controls or watches the Mac, or records the screen.
        case high
        case standard
    }

    /// The database's name, for example `kTCCServiceCamera`.
    public let identifier: String
    public let title: String
    /// The `x-apple.systempreferences` anchor of the list that shows it, or
    /// nil when System Settings has no list of its own for it.
    public let settingsAnchor: String?
    public let risk: Risk
    /// Whether that Settings list has a remove (−) button. Toggle-only lists
    /// can turn access off but keep the record.
    public let settingsCanRemove: Bool

    public var id: String { identifier }

    /// `tccutil`'s name for it: the identifier without its `kTCCService`
    /// prefix, for example `Camera`.
    public var resetName: String {
        identifier.hasPrefix(Self.prefix) ? String(identifier.dropFirst(Self.prefix.count)) : identifier
    }

    /// The anchor for the Privacy & Security page itself.
    public static let privacyAnchor = "Privacy"

    /// The title of the Settings list `settingsAnchor` opens.
    public var settingsPageTitle: String? {
        guard let settingsAnchor else { return nil }
        return Self.pageTitles[settingsAnchor] ?? title
    }

    /// Lists whose title differs from the service's own.
    private static let pageTitles: [String: String] = [
        "Privacy_Accessibility": "Accessibility",
        "Privacy_ListenEvent": "Input Monitoring",
        "Privacy_ScreenCapture": "Screen & System Audio Recording",
        "Privacy_FilesAndFolders": "Files & Folders",
        "Privacy_Photos": "Photos",
        "Privacy_Contacts": "Contacts",
    ]

    static let prefix = "kTCCService"

    init(_ identifier: String, _ title: String, anchor: String?, risk: Risk = .standard, canRemove: Bool = false) {
        self.identifier = identifier
        self.title = title
        self.settingsAnchor = anchor
        self.risk = risk
        self.settingsCanRemove = canRemove
    }

    // MARK: - Lookup

    /// The catalog entry for `identifier`, or a derived one for a service
    /// the catalog does not know.
    public static func named(_ identifier: String) -> PrivacyService {
        if let known = byIdentifier[identifier] { return known }
        return PrivacyService(identifier, derivedTitle(identifier), anchor: nil)
    }

    /// "kTCCServiceSystemPolicyFooBar" → "System Policy Foo Bar".
    static func derivedTitle(_ identifier: String) -> String {
        let name = identifier.hasPrefix(prefix) ? String(identifier.dropFirst(prefix.count)) : identifier
        guard !name.isEmpty else { return identifier }
        var title = ""
        var previous: Character?
        for character in name {
            if let previous, character.isUppercase, previous.isLowercase || previous.isNumber { title.append(" ") }
            title.append(character)
            previous = character
        }
        return title
    }

    private static let byIdentifier: [String: PrivacyService] =
        Dictionary(uniqueKeysWithValues: known.map { ($0.identifier, $0) })

    // MARK: - Catalog

    /// Ordered as System Settings lists them, high-risk services first.
    public static let known: [PrivacyService] = [
        // Titles of the three device-control services match PermissionService's.
        PrivacyService("kTCCServiceSystemPolicyAllFiles", "Full Disk Access", anchor: "Privacy_AllFiles", risk: .high, canRemove: true),
        PrivacyService("kTCCServiceAccessibility", "Accessibility", anchor: "Privacy_Accessibility", risk: .high, canRemove: true),
        PrivacyService("kTCCServicePostEvent", "Event generation", anchor: "Privacy_Accessibility", risk: .high),
        PrivacyService("kTCCServiceListenEvent", "Input monitoring", anchor: "Privacy_ListenEvent", risk: .high, canRemove: true),
        PrivacyService("kTCCServiceScreenCapture", "Screen & System Audio Recording", anchor: "Privacy_ScreenCapture", risk: .high, canRemove: true),
        PrivacyService("kTCCServiceAudioCapture", "System Audio Recording Only", anchor: "Privacy_ScreenCapture", risk: .high),
        PrivacyService("kTCCServiceRemoteDesktop", "Remote Desktop", anchor: "Privacy_RemoteDesktop", risk: .high),
        PrivacyService("kTCCServiceCamera", "Camera", anchor: "Privacy_Camera"),
        PrivacyService("kTCCServiceMicrophone", "Microphone", anchor: "Privacy_Microphone"),
        PrivacyService("kTCCServicePhotos", "Photos", anchor: "Privacy_Photos"),
        PrivacyService("kTCCServicePhotosAdd", "Photos (add only)", anchor: "Privacy_Photos"),
        PrivacyService("kTCCServiceAddressBook", "Contacts", anchor: "Privacy_Contacts"),
        PrivacyService("kTCCServiceContactsFull", "Contacts (full)", anchor: "Privacy_Contacts"),
        PrivacyService("kTCCServiceContactsLimited", "Contacts (basic)", anchor: "Privacy_Contacts"),
        PrivacyService("kTCCServiceCalendar", "Calendars", anchor: "Privacy_Calendars"),
        PrivacyService("kTCCServiceReminders", "Reminders", anchor: "Privacy_Reminders"),
        PrivacyService("kTCCServiceAppleEvents", "Automation", anchor: "Privacy_Automation"),
        PrivacyService("kTCCServiceSystemPolicyDesktopFolder", "Desktop folder", anchor: "Privacy_FilesAndFolders"),
        PrivacyService("kTCCServiceSystemPolicyDocumentsFolder", "Documents folder", anchor: "Privacy_FilesAndFolders"),
        PrivacyService("kTCCServiceSystemPolicyDownloadsFolder", "Downloads folder", anchor: "Privacy_FilesAndFolders"),
        PrivacyService("kTCCServiceSystemPolicyNetworkVolumes", "Network volumes", anchor: "Privacy_FilesAndFolders"),
        PrivacyService("kTCCServiceSystemPolicyRemovableVolumes", "Removable volumes", anchor: "Privacy_FilesAndFolders"),
        PrivacyService("kTCCServiceFileProviderDomain", "Files managed by another app", anchor: "Privacy_FilesAndFolders"),
        PrivacyService("kTCCServiceFileProviderPresence", "File provider presence", anchor: nil),
        PrivacyService("kTCCServiceSystemPolicyAppBundles", "App Management", anchor: "Privacy_AppBundles", canRemove: true),
        PrivacyService("kTCCServiceSystemPolicyAppData", "Data from other apps", anchor: nil),
        PrivacyService("kTCCServiceDeveloperTool", "Developer Tools", anchor: "Privacy_DevTools", canRemove: true),
        PrivacyService("kTCCServiceSystemPolicyDeveloperFiles", "Software development files", anchor: nil),
        PrivacyService("kTCCServiceSystemPolicySysAdminFiles", "System administration files", anchor: nil),
        PrivacyService("kTCCServiceBluetoothAlways", "Bluetooth", anchor: "Privacy_Bluetooth", canRemove: true),
        PrivacyService("kTCCServiceMediaLibrary", "Media & Apple Music", anchor: "Privacy_Media", canRemove: true),
        PrivacyService("kTCCServiceSpeechRecognition", "Speech Recognition", anchor: "Privacy_SpeechRecognition"),
        PrivacyService("kTCCServiceMotion", "Motion & Fitness", anchor: "Privacy_Motion"),
        PrivacyService("kTCCServiceWillow", "Home", anchor: "Privacy_HomeKit"),
        PrivacyService("kTCCServiceFocusStatus", "Focus", anchor: "Privacy_Focus"),
        PrivacyService("kTCCServiceWebBrowserPublicKeyCredential", "Passkeys Access for Web Browsers", anchor: "Privacy_PasskeyAccess"),
        PrivacyService("kTCCServiceLocation", "Location Services", anchor: "Privacy_LocationServices"),
        PrivacyService("kTCCServiceSiri", "Siri", anchor: nil),
        PrivacyService("kTCCServiceGameCenterFriends", "Game Center friends", anchor: nil),
        PrivacyService("kTCCServiceVoiceBanking", "Personal Voice", anchor: nil),
    ]

    /// The per-user lists to open in System Settings when the per-user
    /// database cannot be read (macOS 27 keeps it out of reach). One entry
    /// per Settings list, in its order.
    public static let userLevelSettingsLists: [(title: String, anchor: String)] = [
        ("Camera", "Privacy_Camera"),
        ("Microphone", "Privacy_Microphone"),
        ("Photos", "Privacy_Photos"),
        ("Contacts", "Privacy_Contacts"),
        ("Calendars", "Privacy_Calendars"),
        ("Reminders", "Privacy_Reminders"),
        ("Files & Folders", "Privacy_FilesAndFolders"),
        ("Automation", "Privacy_Automation"),
        ("Media & Apple Music", "Privacy_Media"),
        ("Speech Recognition", "Privacy_SpeechRecognition"),
        ("Home", "Privacy_HomeKit"),
        ("Focus", "Privacy_Focus"),
        ("Motion & Fitness", "Privacy_Motion"),
        ("Passkeys Access for Web Browsers", "Privacy_PasskeyAccess"),
    ]
}
