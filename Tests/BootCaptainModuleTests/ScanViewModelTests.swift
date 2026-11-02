import XCTest
import BootCaptainCore
import BootCaptainKit
@testable import BootCaptainModule

/// The pane's side of the reviewed inventory, fed fixture scan results; no
/// test here runs the live scanner.
@MainActor
final class ScanViewModelTests: XCTestCase {
    private final class Counter {
        var value = 0
    }

    private let rechecks = Counter()
    private lazy var store: ReviewedInventoryStore = {
        let name = "BootCaptainModuleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return ReviewedInventoryStore(defaults: defaults)
    }()

    private func makeModel() -> ScanViewModel {
        let rechecks = self.rechecks
        return ScanViewModel(reviewStore: store, reviewDidChange: { rechecks.value += 1 })
    }

    private func result(_ labels: [String]) -> ScanResult {
        ScanResult(items: labels.map { StartupItem(id: "launchAgent:\($0)", mechanism: .launchAgent,
                                                   label: $0, displayName: $0) },
                   coverage: CoverageReport(), generatedAt: 0)
    }

    func testFirstScanBecomesTheReviewedInventory() throws {
        let model = makeModel()
        XCTAssertEqual(model.review, .notYetReviewed)

        model.apply(result(["com.vendor.a", "com.vendor.b"]))

        guard case .reviewed(let inventory) = store.reviewedInventory() else { return XCTFail("not seeded") }
        XCTAssertEqual(inventory.itemIDs, ["launchAgent:com.vendor.a", "launchAgent:com.vendor.b"])
        XCTAssertTrue(model.unreviewedItems.isEmpty)
        XCTAssertEqual(rechecks.value, 1)
    }

    func testLaterScansShowNewItemsUntilMarkedReviewed() {
        let model = makeModel()
        model.apply(result(["com.vendor.a"]))
        model.apply(result(["com.vendor.a", "com.vendor.new"]))

        XCTAssertEqual(model.unreviewedItems.map(\.id), ["launchAgent:com.vendor.new"])
        model.showUnreviewed()
        XCTAssertEqual(model.filteredItems.map(\.id), ["launchAgent:com.vendor.new"])
        XCTAssertNil(model.selection)

        model.markReviewed()
        XCTAssertTrue(model.unreviewedItems.isEmpty)
        XCTAssertEqual(model.filter, .all)
        XCTAssertEqual(rechecks.value, 2)

        // A new model (the app relaunched) reads the same review.
        XCTAssertTrue(makeModel().review == model.review)
    }

    func testAnUnreadableReviewIsNotSilentlyReplaced() throws {
        let name = "BootCaptainModuleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("garbage".utf8), forKey: ReviewedInventoryStore.defaultsKey)

        let model = ScanViewModel(reviewStore: ReviewedInventoryStore(defaults: defaults), reviewDidChange: {})
        model.apply(result(["com.vendor.a"]))

        XCTAssertEqual(model.review, .unreadable)
        XCTAssertEqual(defaults.data(forKey: ReviewedInventoryStore.defaultsKey), Data("garbage".utf8))
    }

    func testMarkReviewedNeedsACompletedScan() {
        let model = makeModel()
        model.markReviewed()
        XCTAssertEqual(store.reviewedInventory(), .notYetReviewed)
        XCTAssertEqual(rechecks.value, 0)
    }
}
