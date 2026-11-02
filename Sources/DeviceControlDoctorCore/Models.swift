import Foundation

public enum PermissionService: String, CaseIterable, Codable, Identifiable, Sendable {
    case accessibility = "Accessibility"
    case postEvent = "PostEvent"
    case listenEvent = "ListenEvent"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .postEvent: return "Event generation"
        case .listenEvent: return "Input monitoring"
        }
    }
    public var explanation: String {
        switch self {
        case .accessibility: return "Read and control other apps’ interfaces."
        case .postEvent: return "Generate keyboard and mouse events."
        case .listenEvent: return "Observe keyboard and mouse input."
        }
    }
    public var settingsAnchor: String {
        self == .listenEvent ? "Privacy_ListenEvent" : "Privacy_Accessibility"
    }
}

public enum AuthorizationState: String, Codable, Sendable {
    case granted, denied, limited, unknown, unavailable
    public var title: String { rawValue.capitalized }
}

public struct AuthorizationResult: Codable, Equatable, Sendable {
    public var state: AuthorizationState
    public var detail: String
    public init(state: AuthorizationState, detail: String) {
        self.state = state
        self.detail = detail
    }
}

public struct PermissionReading: Codable, Identifiable, Sendable {
    public var service: PermissionService
    public var result: AuthorizationResult
    public var checkedAt: Date
    public var id: String { service.rawValue }
    public init(service: PermissionService, result: AuthorizationResult, checkedAt: Date = Date()) {
        self.service = service; self.result = result; self.checkedAt = checkedAt
    }
}

public struct AppIdentity: Codable, Equatable, Sendable {
    public var signingIdentifier: String = ""
    public var teamIdentifier: String = ""
    public var requirement: String = ""
    public var signatureValid: Bool? = nil
    public var signatureDetail: String = "Not checked"
    public init() {}
}

public struct WatchedApp: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var bundleID: String
    public var path: String
    public var version: String
    public var expectedServices: [PermissionService] = []
    public var readings: [PermissionReading] = []
    public var identity: AppIdentity = AppIdentity()
    public var identityChangedAt: Date?
    public var functionalTest: FunctionalTest?
    public var lastKnownWorking: Date?
    public init(name: String, bundleID: String, path: String, version: String) {
        self.name = name; self.bundleID = bundleID; self.path = path; self.version = version
    }
    public var canReset: Bool {
        ClientIdentifier.isBundleIdentifier(bundleID)
    }
    public var hasDeniedExpectedPermission: Bool {
        readings.contains { expectedServices.contains($0.service) && $0.result.state == .denied }
    }
    public var hasFailedTest: Bool { functionalTest?.outcome == .failed }
    public var summary: String {
        if hasFailedTest { return "Test failed" }
        if hasDeniedExpectedPermission { return "Review access" }
        if expectedServices.isEmpty { return "Choose permissions" }
        let expected = readings.filter { expectedServices.contains($0.service) }
        if expected.count == expectedServices.count && expected.allSatisfy({ $0.result.state == .granted }) {
            return functionalTest?.outcome == .passed ? "Last test passed" : "Granted · untested"
        }
        return readings.isEmpty ? "Not checked" : "Needs verification"
    }
}

public enum FunctionalOutcome: String, Codable, Sendable { case passed, failed, inconclusive }

public struct FunctionalTest: Codable, Sendable {
    public var outcome: FunctionalOutcome
    public var recordedAt: Date
    public var note: String
    public var appPath: String
    public var appVersion: String
    public init(outcome: FunctionalOutcome, note: String, appPath: String, appVersion: String, recordedAt: Date = Date()) {
        self.outcome = outcome; self.note = note; self.appPath = appPath
        self.appVersion = appVersion; self.recordedAt = recordedAt
    }
}

public struct DoctorEvent: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var date: Date = Date()
    public var appID: UUID?
    public var appName: String
    public var message: String
    public init(appID: UUID? = nil, appName: String, message: String) { self.appID = appID; self.appName = appName; self.message = message }
}

public enum ClientIdentifier {
    public static func isBundleIdentifier(_ value: String) -> Bool {
        value.range(of: "\\A[A-Za-z0-9][A-Za-z0-9_-]*(?:\\.[A-Za-z0-9_-]+)+\\z", options: .regularExpression) != nil
    }
}
