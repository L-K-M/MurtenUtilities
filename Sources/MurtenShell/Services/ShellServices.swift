import Foundation
import MurtenCore

/// Persists `SuiteSettings`.
public protocol SettingsPersisting {
    func load() -> SuiteSettings
    func save(_ settings: SuiteSettings)
}

/// Whether the user allowed notifications for the app as a whole.
public enum NotificationAuthorization: Equatable, Sendable {
    case granted
    case denied
    /// No app bundle (e.g. `swift run`); notifications cannot work.
    case unsupported
}

/// Delivers opted-in suggestions as system notifications.
@MainActor
public protocol SuggestionNotifying: AnyObject {
    /// Called with the validated-later route URL when the user clicks one.
    var onOpen: ((URL) -> Void)? { get set }
    func requestAuthorization() async -> NotificationAuthorization
    func deliver(_ suggestion: Suggestion, moduleName: String)
    /// Withdraws delivered notifications of these modules, so none outlives
    /// the user turning them (or the companion) off.
    func withdraw(modules moduleIDs: Set<String>)
}

/// Samples power, network and time for the watch gate.
public protocol WatchEnvironmentSampling: Sendable {
    func sample() async -> WatchEnvironment
}

public enum LaunchAtLoginStatus: Equatable, Sendable {
    case disabled
    case enabled
    /// Registered, waiting for the user in System Settings › Login Items.
    case requiresApproval
    /// No app bundle; the login item cannot be registered.
    case unsupported
}

public enum LaunchAtLoginRequest: Sendable {
    case register
    case unregister
}

@MainActor
public protocol LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus { get }
    func apply(_ request: LaunchAtLoginRequest) throws
}

/// Calls back when the Mac wakes from sleep.
@MainActor
public protocol SystemWakeObserving: AnyObject {
    func observeWake(_ handler: @escaping @MainActor () -> Void)
}

/// A published suite release newer than the running build.
public struct SuiteRelease: Equatable, Sendable {
    public let version: ReleaseVersion
    public let pageURL: URL

    public init(version: ReleaseVersion, pageURL: URL) {
        self.version = version
        self.pageURL = pageURL
    }
}

/// Looks up the suite's latest published release.
public protocol SuiteUpdateChecking: Sendable {
    func latestRelease() async throws -> SuiteRelease
}

/// The side-effecting dependencies of `AppModel`, swappable for fakes.
@MainActor
public struct ShellServices {
    public var settings: any SettingsPersisting
    public var suggestionPersistence: any SuggestionPersisting
    public var notifier: any SuggestionNotifying
    public var environment: any WatchEnvironmentSampling
    public var launchAtLogin: any LaunchAtLoginControlling
    public var wake: any SystemWakeObserving
    public var updates: any SuiteUpdateChecking
    public var clock: any WatchClock
    /// The running build's version, e.g. from `CFBundleShortVersionString`.
    public var currentVersion: ReleaseVersion?
    /// Module-scoped preferences, one domain per module id.
    public var moduleDefaults: (String) -> UserDefaults
    /// Persists the last update check across launches.
    public var stateDefaults: UserDefaults

    public init(settings: any SettingsPersisting, suggestionPersistence: any SuggestionPersisting,
                notifier: any SuggestionNotifying, environment: any WatchEnvironmentSampling,
                launchAtLogin: any LaunchAtLoginControlling, wake: any SystemWakeObserving,
                updates: any SuiteUpdateChecking, clock: any WatchClock, currentVersion: ReleaseVersion?,
                moduleDefaults: @escaping (String) -> UserDefaults, stateDefaults: UserDefaults) {
        self.settings = settings
        self.suggestionPersistence = suggestionPersistence
        self.notifier = notifier
        self.environment = environment
        self.launchAtLogin = launchAtLogin
        self.wake = wake
        self.updates = updates
        self.clock = clock
        self.currentVersion = currentVersion
        self.moduleDefaults = moduleDefaults
        self.stateDefaults = stateDefaults
    }
}
