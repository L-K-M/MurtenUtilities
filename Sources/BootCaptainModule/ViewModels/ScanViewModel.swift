import Foundation
import SwiftUI
import BootCaptainCore
import BootCaptainKit

/// Drives scanning and diagnosis off the main actor and publishes results for
/// the UI. Grouping and filtering live here so the views stay declarative.
/// The provider owns it, so results and the selection survive navigation.
///
/// It also keeps the reviewed inventory the background check compares
/// against: seeded by the first completed scan, replaced when the user marks
/// the list as reviewed.
@MainActor
final class ScanViewModel: ObservableObject {
    @Published var items: [StartupItem] = []
    @Published var coverage: CoverageReport = CoverageReport()
    @Published var isScanning = false
    @Published var lastScan: Date?
    @Published var searchText = "" {
        didSet { reconcileSelection() }
    }
    @Published var filter: Filter = .all {
        didSet { reconcileSelection() }
    }
    @Published var selection: StartupItem.ID?
    @Published private(set) var review: ReviewedInventoryLookup

    private let reviewStore: ReviewedInventoryStore
    private let reviewDidChange: @MainActor () -> Void

    init(reviewStore: ReviewedInventoryStore, reviewDidChange: @escaping @MainActor () -> Void) {
        self.reviewStore = reviewStore
        self.reviewDidChange = reviewDidChange
        review = reviewStore.reviewedInventory()
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case unreviewed = "New since last review"
        case thirdParty = "Third-party"
        case launchesAtLogin = "Launches at login"
        case orphans = "Orphaned / broken"
        case failing = "Failure evidence"
        var id: String { rawValue }
    }

    func scan(diagnose: Bool) {
        guard !isScanning else { return }
        isScanning = true
        Task.detached(priority: .userInitiated) {
            let ctx = SystemEnvironment.makeContext()
            let raw = BootCaptainKit.Scanner().scan(ctx, now: Date().timeIntervalSince1970)
            // Bind an immutable result so the MainActor closure captures a Sendable
            // value, not a mutable variable (Swift 6 concurrency safety).
            let result = diagnose
                ? ScanResult(items: DiagnosisEngine().diagnose(items: raw.items, ctx: ctx),
                             coverage: raw.coverage, generatedAt: raw.generatedAt)
                : raw
            await MainActor.run {
                self.apply(result)
            }
        }
    }

    /// Publishes a finished scan. The first one also becomes the reviewed
    /// inventory: whatever the user sees on first opening the pane is
    /// what later checks compare against.
    func apply(_ result: ScanResult) {
        items = result.items
        reconcileSelection()
        coverage = result.coverage
        isScanning = false
        lastScan = Date()

        if review == .notYetReviewed { markReviewed() }
    }

    // MARK: Review

    /// Items not in the reviewed inventory. Empty until a review exists.
    var unreviewedItems: [StartupItem] {
        items.filter(isUnreviewed)
    }

    /// Makes the last completed scan the reviewed inventory and asks the
    /// suite to re-check, so suggestions about these items resolve.
    func markReviewed() {
        guard lastScan != nil else { return }
        let inventory = ReviewedInventory(reviewedAt: Date(), itemIDs: Set(items.map(\.id)))
        guard reviewStore.save(inventory) else { return }
        review = .reviewed(inventory)
        // The new items just became reviewed; show the whole list again
        // rather than an empty filter.
        if filter == .unreviewed { filter = .all }
        reconcileSelection()
        reviewDidChange()
    }

    /// What a "review" route opens on: the unreviewed items, unfiltered by
    /// search. Selects nothing; the user picks what to look at.
    func showUnreviewed() {
        searchText = ""
        filter = .unreviewed
        selection = nil
    }

    private func isUnreviewed(_ item: StartupItem) -> Bool {
        guard case .reviewed(let inventory) = review else { return false }
        return !inventory.contains(item.id)
    }

    /// Items after search + filter, grouped by tier for the sidebar/list.
    var filteredItems: [StartupItem] {
        items.filter(isDisplayed)
    }

    var groupedByTier: [(Mechanism.Tier, [StartupItem])] {
        let groups = Dictionary(grouping: filteredItems, by: { $0.mechanism.tier })
        let order: [Mechanism.Tier] = [.core, .legacy, .advanced]
        return order.compactMap { tier in
            guard let items = groups[tier], !items.isEmpty else { return nil }
            return (tier, items.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending })
        }
    }

    func displayedItem(id: StartupItem.ID?) -> StartupItem? {
        guard let id else { return nil }
        return filteredItems.first { $0.id == id }
    }

    private func reconcileSelection() {
        guard let selection else { return }
        if !items.contains(where: {
            $0.id == selection && isDisplayed($0)
        }) {
            self.selection = nil
        }
    }

    private func isDisplayed(_ item: StartupItem) -> Bool {
        matchesFilter(item) && matchesSearch(item)
    }

    private func matchesFilter(_ item: StartupItem) -> Bool {
        switch filter {
        case .all: return true
        case .unreviewed: return isUnreviewed(item)
        case .thirdParty:
            return !(item.trust == .applePlatform || item.trust == .appleDistributed)
        case .launchesAtLogin: return item.triggers.runsAtStartup
        case .orphans: return item.health == .possiblyOrphaned || item.health == .broken
        case .failing: return item.diagnosis?.state == .failureEvidence
        }
    }

    private func matchesSearch(_ item: StartupItem) -> Bool {
        guard !searchText.isEmpty else { return true }
        let needle = searchText.lowercased()
        return item.displayName.lowercased().contains(needle)
            || (item.label?.lowercased().contains(needle) ?? false)
            || (item.attribution.vendorName?.lowercased().contains(needle) ?? false)
            || (item.sourcePath?.lowercased().contains(needle) ?? false)
    }
}
