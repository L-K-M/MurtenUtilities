import Foundation
import MurtenCore
import MurtenModuleKit
import ShortkingCore
import ShortkingKit
import SwiftUI

/// Shortking inside Murten Utilities: the standalone app's window as a pane,
/// plus a background check for shortcut conflicts nobody has acknowledged.
///
/// The pane's state (`AppState`: the inventory, the detective session, the
/// attribution ledger) is created the first time the pane opens and kept for
/// the app's lifetime, so a launch that never opens Shortking reads none of
/// its files.
@MainActor
public final class ShortkingProvider: SuiteModuleProvider {

    /// The module id for the app's catalog. Nonisolated so the catalog can
    /// name it outside the main actor; not called `moduleID`, which the
    /// instance requirement needs to itself.
    public nonisolated static let identifier = ShortkingSuite.moduleID

    public let moduleID = ShortkingSuite.moduleID
    public let watch: WatcherRegistration?

    private let context: ModuleContext
    private let acknowledgements: ConflictAcknowledgements
    private var state: AppState?

    public init(context: ModuleContext) {
        self.context = context
        acknowledgements = ConflictAcknowledgements(defaults: context.defaults)
        watch = WatcherRegistration(
            watcher: ShortkingWatcher(inventory: LiveShortcutInventory(acknowledgements: acknowledgements)),
            rule: ShortcutConflictRule()
        )
    }

    public var routeActions: [String: Set<String>] { ShortkingSuite.routeActions }

    /// Shortking needs macOS 14; the suite's floor is 26. Missing grants and
    /// SkyLight symbols degrade single sources, which the pane's Health screen
    /// reports, rather than the whole module.
    public func applicability() async -> Applicability { .applicable }

    public func makePane(route: ModuleRoute?) -> AnyView {
        AnyView(ShortkingPane(route: route).environmentObject(appState))
    }

    private var appState: AppState {
        if let state { return state }
        let made = AppState(
            settingsStore: ShortkingSettingsStore(
                defaults: context.defaults,
                legacyFile: StoreLocation.directoryURL.appendingPathComponent(SettingsStore.filename)
            ),
            acknowledgements: acknowledgements,
            requestRecheck: context.requestRecheck
        )
        state = made
        return made
    }
}
