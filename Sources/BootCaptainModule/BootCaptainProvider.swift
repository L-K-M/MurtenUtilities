import SwiftUI
import MurtenCore
import MurtenModuleKit
import BootCaptainCore

/// BootCaptain inside Murten Utilities: the startup-item inventory and boot
/// audit as a pane, plus a background check for startup items added since
/// the user last reviewed the list.
///
/// The provider owns the scan, the cleanup history and the helper stand-in,
/// so they survive navigating home and back. Files the standalone app keeps
/// stay where they are: the Clean Up vault and journal in
/// `~/Library/Application Support/BootCaptain` (`CleanupService`).
@MainActor
public final class BootCaptainProvider: SuiteModuleProvider {
    public let moduleID = StartupWatch.moduleID
    /// "review" opens the list of items added since the last review. It
    /// selects nothing and changes nothing.
    public let routeActions: [String: Set<String>] = [StartupWatch.reviewAction: []]
    public let watch: WatcherRegistration?

    let scan: ScanViewModel
    let cleanup = CleanupService()
    private let helper = HelperClient()

    /// - Parameter inventory: what the background check reads; the live
    ///   launchd folders unless a test substitutes fixtures.
    public init(context: ModuleContext,
                inventory: any StartupInventoryObserving = LaunchdFolderInventory.live()) {
        let reviewStore = ReviewedInventoryStore(defaults: context.defaults)
        scan = ScanViewModel(reviewStore: reviewStore, reviewDidChange: context.requestRecheck)
        watch = WatcherRegistration(
            watcher: StartupItemsWatcher(inventory: inventory, reviewed: reviewStore),
            rule: NewStartupItemsRule())
    }

    public func makePane(route: ModuleRoute?) -> AnyView {
        AnyView(BootCaptainPane(route: route, scan: scan, helper: helper, cleanup: cleanup))
    }

    public var interruptionWarning: String? {
        cleanup.isWorking ? "Startup items are still being moved to or from the vault." : nil
    }
}
