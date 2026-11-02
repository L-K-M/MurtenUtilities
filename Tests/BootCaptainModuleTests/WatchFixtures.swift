import Foundation
import MurtenCore
import BootCaptainCore
@testable import BootCaptainModule

let fixtureDate = Date(timeIntervalSince1970: 1_800_000_000)

/// A fixed inventory, as if read from disk.
struct FixtureInventory: StartupInventoryObserving {
    var snapshot: StartupInventorySnapshot

    func observeInventory() async -> StartupInventorySnapshot { snapshot }
}

/// A fixed reviewed inventory.
struct FixtureReviewed: ReviewedInventoryReading {
    var lookup: ReviewedInventoryLookup

    func reviewedInventory() -> ReviewedInventoryLookup { lookup }
}

func agent(_ label: String, app: AppIdentity? = nil, associated: [String] = [],
           mechanism: Mechanism = .launchAgent) -> WatchedStartupItem {
    WatchedStartupItem(id: "\(mechanism.rawValue):\(label)", mechanism: mechanism, label: label,
                       sourcePath: "/Library/LaunchAgents/\(label).plist", owningApp: app,
                       associatedBundleIdentifiers: associated)
}

func reviewed(_ items: [WatchedStartupItem]) -> ReviewedInventory {
    ReviewedInventory(reviewedAt: fixtureDate, itemIDs: Set(items.map(\.id)))
}

func watcher(_ items: [WatchedStartupItem], reviewed lookup: ReviewedInventoryLookup,
             installedApps: [String: String] = [:],
             failures: [InventoryReadFailure] = []) -> StartupItemsWatcher {
    StartupItemsWatcher(
        inventory: FixtureInventory(snapshot: StartupInventorySnapshot(
            items: items, installedApps: installedApps, failures: failures)),
        reviewed: FixtureReviewed(lookup: lookup),
        now: { fixtureDate })
}
