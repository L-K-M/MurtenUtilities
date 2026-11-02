import SwiftUI
import MurtenCore
import MurtenModuleKit
import ZenBackupManagerCore

/// Where the module finds Zen's profiles and keeps its safety copies.
public struct ZenBackupLocations: Sendable {
    public let zenRoot: URL
    public let safetyRoot: URL

    public init(zenRoot: URL, safetyRoot: URL) {
        self.zenRoot = zenRoot
        self.safetyRoot = safetyRoot
    }

    /// The standalone app's locations. Safety copies stay in
    /// ~/Library/Application Support/ZenBackupManager, so undo still sees the
    /// ones the standalone app took.
    public static var standard: ZenBackupLocations {
        ZenBackupLocations(zenRoot: ProfileDiscovery.zenRoot, safetyRoot: SafetyArchive.defaultRoot)
    }
}

/// Zen Backup Manager in the suite: the timeline pane, a settings tab and a
/// watcher for profiles whose newest session snapshot is a week old.
@MainActor
public final class ZenBackupManagerProvider: SuiteModuleProvider {
    public let moduleID = ZenBackupRoute.moduleID
    public let routeActions: [String: Set<String>] = [ZenBackupRoute.timelineAction: [ZenBackupRoute.profileKey]]
    public let watch: WatcherRegistration?

    static let notInstalled = "Zen Browser is not installed"

    private let locations: ZenBackupLocations
    let model: AppModel

    public init(locations: ZenBackupLocations = .standard) {
        self.locations = locations
        model = AppModel(zenRoot: locations.zenRoot, safetyRoot: locations.safetyRoot)
        watch = WatcherRegistration(watcher: ZenSessionWatcher(source: SessionSnapshotReader(zenRoot: locations.zenRoot)),
                                    rule: SessionStalenessRule())
    }

    /// Applicable while Zen lists at least one profile. Reads profiles.ini
    /// only, off the main actor; never prompts.
    public func applicability() async -> Applicability {
        let root = locations.zenRoot
        let listed = await Task.detached(priority: .utility) {
            Result { try ProfileDiscovery.discover(root: root).isEmpty == false }
        }.value

        switch listed {
        case .success(true):
            return .applicable
        case .success(false):
            return .inapplicable(reason: Self.notInstalled)
        case .failure(let error):
            return .inapplicable(reason: "Zen's profile list could not be read: \(error.localizedDescription)")
        }
    }

    public func makePane(route: ModuleRoute?) -> AnyView {
        AnyView(ContentView(model: model, route: route))
    }

    public func makeSettings() -> AnyView? {
        AnyView(ZenBackupSettings(safetyRoot: locations.safetyRoot))
    }

    public var interruptionWarning: String? {
        model.isWritingSession ? "A restore is still writing Zen's session files." : nil
    }
}
