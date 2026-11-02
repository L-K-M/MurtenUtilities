import Foundation
import ShortkingCore
import ShortkingKit

/// The watcher's view of this Mac. Reads only: the pane's saved inventory
/// (never repaired or created here), the system shortcut plist and SkyLight's
/// read-only symbolic hotkey calls, and the acknowledgements in the module's
/// defaults. No Accessibility, no event tap, no probe, no subprocess.
struct LiveShortcutInventory: ShortcutInventoryObserving {

    /// The pane's `claims.json`, where `ClaimDatabase` keeps it.
    let inventoryFile: URL
    let acknowledgements: ConflictAcknowledgements

    init(inventoryFile: URL = StoreLocation.directoryURL.appendingPathComponent(ClaimDatabase.filename),
         acknowledgements: ConflictAcknowledgements) {
        self.inventoryFile = inventoryFile
        self.acknowledgements = acknowledgements
    }

    func savedInventory() throws -> [Claim]? {
        guard FileManager.default.fileExists(atPath: inventoryFile.path) else { return nil }
        return try StoreFileReader.payload([Claim].self, from: Data(contentsOf: inventoryFile))
    }

    func currentSystemShortcuts() async -> [Claim] {
        // The symbolic scanner reads no running or installed apps, so an empty
        // context needs no AppKit snapshot.
        let context = ScanContext(runningApps: [], installedApps: [], options: .default)
        return (try? await SymbolicHotKeyScanner().scan(context: context)) ?? []
    }

    func acknowledgedConflicts() -> Set<String> {
        acknowledgements.signatures
    }
}
