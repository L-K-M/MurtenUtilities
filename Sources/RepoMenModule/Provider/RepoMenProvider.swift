import Combine
import Foundation
import SwiftUI
import MurtenCore
import MurtenModuleKit
import RepoMenCore

/// How the suite's catalog registers RepoMen.
public enum RepoMenModuleFactory {
    public static var factory: ModuleFactory {
        ModuleFactory(moduleID: RepoMenRoutes.moduleID) { context in
            RepoMenProvider(context: context)
        }
    }
}

/// RepoMen inside the suite. The suite creates it once; it owns everything that
/// must outlive the pane (the scan and its selection, the snapshot list, managed
/// storage measurements, auto-trash), because the pane view is rebuilt on every
/// navigation.
@MainActor
final class RepoMenProvider: SuiteModuleProvider {
    let moduleID = RepoMenRoutes.moduleID

    /// A suggestion opens a review (re-scan, nothing checked); the menu section
    /// and log links open the auto-trash log.
    let routeActions: [String: Set<String>] = [
        RepoMenRoutes.reviewAction: [RepoMenRoutes.folderKey],
        RepoMenRoutes.logAction: [],
    ]

    let preferences: Preferences
    let model: AppModel
    let snapshotModel: SnapshotModel
    let managedStorage: ManagedStorageModel
    let autoTrash: AutoTrashController
    let watch: WatcherRegistration?

    private let context: ModuleContext
    private var cancellables: Set<AnyCancellable> = []

    init(context: ModuleContext,
         standaloneValues: [String: Any]? = StandalonePreferencesImport.standaloneValues(),
         observer: any StaleArtifactObserving = LiveStaleArtifactObserver(),
         startsAutoTrash: Bool = true) {
        self.context = context
        // First launch only, with or without a standalone app to import from.
        StandalonePreferencesImport.importOnce(from: standaloneValues ?? [:], into: context.defaults)

        let preferences = Preferences(defaults: context.defaults)
        self.preferences = preferences
        model = AppModel(preferences: preferences)
        snapshotModel = SnapshotModel()
        managedStorage = ManagedStorageModel()
        autoTrash = AutoTrashController(
            preferences: preferences,
            backgroundWorkAllowed: context.backgroundWorkAllowed,
            didTrash: context.requestRecheck)

        // The background check reads a snapshot of the settings on the main actor;
        // the survey itself runs off it.
        let watcher = StaleArtifactWatcher(
            observer: observer,
            settings: { @MainActor [preferences] in preferences.watchSettings })
        watch = WatcherRegistration(watcher: watcher, rule: StaleArtifactRule(home: NSHomeDirectory()))

        observeChanges()
        if startsAutoTrash { autoTrash.start() }
    }

    /// Re-runs the background check soon after something it reports on changed:
    /// a reclaim in the pane, or the folders and threshold it surveys.
    private func observeChanges() {
        let recheck = context.requestRecheck
        model.$summary
            .compactMap { $0 }
            .sink { _ in recheck() }
            .store(in: &cancellables)
        let folders = preferences.$watchedFolders.dropFirst().map { _ in () }
        let roots = preferences.$scanRoots.dropFirst().map { _ in () }
        let idleDays = preferences.$idleDays.dropFirst().map { _ in () }
        Publishers.Merge3(folders, roots, idleDays)
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { _ in recheck() }
            .store(in: &cancellables)
    }

    // MARK: SuiteModuleProvider

    func makePane(route: ModuleRoute?) -> AnyView {
        AnyView(RepoMenPane(route: route, model: model, snapshotModel: snapshotModel,
                            preferences: preferences, managedStorage: managedStorage,
                            autoTrash: autoTrash))
    }

    func makeSettings() -> AnyView? {
        AnyView(SettingsView()
            .environmentObject(preferences)
            .environmentObject(autoTrash))
    }

    func makeMenuSection() -> AnyView? {
        let openRoute = context.open
        return AnyView(RepoMenMenuSection(preferences: preferences, autoTrash: autoTrash) {
            openRoute(ModuleRoute(moduleID: RepoMenRoutes.moduleID, action: RepoMenRoutes.logAction))
        })
    }

    var interruptionWarning: String? {
        if model.isReclaiming { return "A reclaim is still moving or deleting items." }
        if autoTrash.isRunning { return "Auto-trash is moving stale artifacts to the Trash." }
        if snapshotModel.isWorking { return "A Time Machine snapshot operation is still running." }
        return nil
    }
}
