import AppKit
import Foundation
import IOKit.ps
import MurtenCore
import Network
import ServiceManagement
import UserNotifications

// MARK: - Assembly

public extension ShellServices {
    static let bundleIdentifier = "ch.lkmc.MurtenUtilities"

    /// The real services. Suggestion persistence falls back to a temporary
    /// file only when Application Support cannot be located, and says so.
    static func live() -> ShellServices {
        let persistence: any SuggestionPersisting
        if let standard = try? JSONFileSuggestionPersistence.standard() {
            persistence = standard
        } else {
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent(JSONFileSuggestionPersistence.directoryName)
                .appendingPathComponent(JSONFileSuggestionPersistence.fileName)
            persistence = JSONFileSuggestionPersistence(fileURL: fallback)
        }

        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            .flatMap(ReleaseVersion.init)

        return ShellServices(
            settings: UserDefaultsSettingsStore(defaults: .standard),
            suggestionPersistence: persistence,
            notifier: UserNotificationNotifier(),
            environment: SystemWatchEnvironment(),
            launchAtLogin: MainAppLoginItem(),
            wake: WorkspaceWakeObserver(),
            updates: GitHubReleaseChecker(),
            clock: SystemWatchClock(),
            currentVersion: version,
            moduleDefaults: { moduleID in
                UserDefaults(suiteName: "\(bundleIdentifier).\(moduleID)") ?? .standard
            },
            stateDefaults: .standard)
    }
}

// MARK: - Settings

struct UserDefaultsSettingsStore: SettingsPersisting {
    private static let key = "suiteSettings"
    let defaults: UserDefaults

    func load() -> SuiteSettings {
        guard let data = defaults.data(forKey: Self.key) else { return SuiteSettings() }
        // Unreadable settings fall back to the quiet defaults: everything off.
        return (try? JSONDecoder().decode(SuiteSettings.self, from: data)) ?? SuiteSettings()
    }

    func save(_ settings: SuiteSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

// MARK: - Notifications

/// Wraps `UNUserNotificationCenter`. Without an app bundle (`swift run`) the
/// center is unavailable, so every call degrades to `.unsupported`.
@MainActor
final class UserNotificationNotifier: NSObject, SuggestionNotifying, UNUserNotificationCenterDelegate {
    private static let routeKey = "route"
    var onOpen: ((URL) -> Void)?

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    override init() {
        super.init()
        center?.delegate = self
    }

    func requestAuthorization() async -> NotificationAuthorization {
        guard let center else { return .unsupported }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        return granted ? .granted : .denied
    }

    func deliver(_ suggestion: Suggestion, moduleName: String) {
        guard let center else { return }

        let content = UNMutableNotificationContent()
        content.title = suggestion.title
        content.subtitle = moduleName
        content.body = suggestion.detail
        content.threadIdentifier = suggestion.moduleID
        content.userInfo = [Self.routeKey: suggestion.route.url.absoluteString]

        // Same key → replaces the earlier notification instead of stacking.
        let request = UNNotificationRequest(identifier: suggestion.key.description, content: content, trigger: nil)
        center.add(request)
    }

    func withdraw(modules moduleIDs: Set<String>) {
        guard let center, !moduleIDs.isEmpty else { return }
        center.getDeliveredNotifications { delivered in
            let identifiers = delivered
                .filter { moduleIDs.contains($0.request.content.threadIdentifier) }
                .map(\.request.identifier)
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard let text = response.notification.request.content.userInfo[Self.routeKey] as? String,
              let url = URL(string: text) else { return }
        await MainActor.run { onOpen?(url) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.list, .banner]
    }
}

// MARK: - Environment

/// Power source via IOKit, Low Power Mode via ProcessInfo, network cost via
/// `NWPathMonitor`, local time via the current calendar.
final class SystemWatchEnvironment: WatchEnvironmentSampling, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var networkCost: WatchEnvironment.NetworkCost = .unrestricted

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.update(path.isExpensive || path.isConstrained ? .expensive : .unrestricted)
        }
        monitor.start(queue: DispatchQueue(label: "ch.lkmc.MurtenUtilities.network-cost"))
    }

    deinit {
        monitor.cancel()
    }

    private func update(_ cost: WatchEnvironment.NetworkCost) {
        lock.lock(); networkCost = cost; lock.unlock()
    }

    func sample() async -> WatchEnvironment {
        lock.lock(); let cost = networkCost; lock.unlock()
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return WatchEnvironment(
            powerSource: Self.powerSource(),
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            networkCost: cost,
            minuteOfDay: (now.hour ?? 0) * 60 + (now.minute ?? 0))
    }

    private static func powerSource() -> WatchEnvironment.PowerSource {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else { return .adapter }
        return (type as String) == kIOPMBatteryPowerKey ? .battery : .adapter
    }
}

// MARK: - Login item

/// `SMAppService.mainApp`, the documented way for an app to launch itself at
/// login. Only meaningful inside an app bundle.
@MainActor
struct MainAppLoginItem: LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus {
        guard Bundle.main.bundleIdentifier != nil else { return .unsupported }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered, .notFound: return .disabled
        @unknown default: return .disabled
        }
    }

    func apply(_ request: LaunchAtLoginRequest) throws {
        switch request {
        case .register: try SMAppService.mainApp.register()
        case .unregister: try SMAppService.mainApp.unregister()
        }
    }
}

// MARK: - Wake

@MainActor
final class WorkspaceWakeObserver: SystemWakeObserving {
    private var token: NSObjectProtocol?

    func observeWake(_ handler: @escaping @MainActor () -> Void) {
        if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler() }
            }
    }
}

// MARK: - Updates

/// Reads the latest release of L-K-M/MurtenUtilities from the GitHub REST
/// API. Runs only when the user turned update checks on.
struct GitHubReleaseChecker: SuiteUpdateChecking {
    static let endpoint = URL(string: "https://api.github.com/repos/L-K-M/MurtenUtilities/releases/latest")!
    static let statusOK = 200

    enum CheckError: Error {
        case unexpectedStatus(Int)
        case unreadableTag(String)
    }

    private struct Payload: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    func latestRelease() async throws -> SuiteRelease {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // URLSession sends a default agent; name the app so GitHub can tell.
        request.setValue(ShellServices.bundleIdentifier, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == Self.statusOK else { throw CheckError.unexpectedStatus(status) }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let version = ReleaseVersion(payload.tagName) else { throw CheckError.unreadableTag(payload.tagName) }
        return SuiteRelease(version: version, pageURL: payload.htmlURL)
    }
}
