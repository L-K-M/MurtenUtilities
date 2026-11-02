import SwiftUI
import MurtenCore
import MurtenModuleKit
import BootCaptainCore

/// The standalone app's window content as a suite pane. Its scene-level
/// pieces moved here: the environment objects (owned by the provider), the
/// Rescan and Boot Audit commands (now in the suite's Tool menu) and the
/// scan on appearance.
struct BootCaptainPane: View {
    let route: ModuleRoute?
    @ObservedObject var scan: ScanViewModel
    let helper: HelperClient
    let cleanup: CleanupService

    var body: some View {
        ContentView()
            .environmentObject(scan)
            .environmentObject(helper)
            .environmentObject(cleanup)
            .moduleCommands([
                ModuleCommand("Rescan", shortcut: KeyboardShortcut("r"), isEnabled: !scan.isScanning) {
                    scan.scan(diagnose: false)
                },
                ModuleCommand("Run Boot Audit", shortcut: KeyboardShortcut("r", modifiers: [.command, .shift]),
                              isEnabled: !scan.isScanning) {
                    scan.scan(diagnose: true)
                },
            ])
            .onAppear {
                // A suggestion opens on what is new; it never starts a
                // change. The pane re-scans either way, as the app did.
                if route?.action == StartupWatch.reviewAction { scan.showUnreviewed() }
                scan.scan(diagnose: false)
            }
    }
}
