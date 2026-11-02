import XCTest
import MurtenCore
@testable import BootCaptainCore
@testable import BootCaptainModule

final class StartupInventoryDiffTests: XCTestCase {
    func testOnlyUnreviewedItemsAreNewAndEachIdCountsOnce() {
        let old = agent("com.vendor.old")
        let new = agent("com.vendor.new")
        let groups = StartupInventoryDiff.newItemsByProduct(
            current: [old, new, new], reviewed: reviewed([old]))

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].items.map(\.label), ["com.vendor.new"])
    }

    func testNothingNewWhenEverythingWasReviewed() {
        let items = [agent("com.vendor.a"), agent("com.vendor.b")]
        XCTAssertTrue(StartupInventoryDiff.newItemsByProduct(current: items, reviewed: reviewed(items)).isEmpty)
    }

    func testGroupsByOwningAppThenAssociatedAppThenCatalogThenVendor() {
        let docker = AppIdentity(name: "Docker", bundleIdentifier: "com.docker.docker")
        let items = [
            agent("com.docker.helper", app: docker, mechanism: .smAppServiceDaemon),
            agent("com.docker.socket", associated: ["com.docker.docker"]),
            agent("com.google.keystone.agent"),
            agent("com.example.sync"),
            agent("com.example.updater"),
            agent("loose-label"),
        ]
        let groups = StartupInventoryDiff.newItemsByProduct(
            current: items, reviewed: ReviewedInventory(reviewedAt: fixtureDate, itemIDs: []),
            installedApps: ["com.docker.docker": "Docker"])

        let byName = Dictionary(uniqueKeysWithValues: groups.map { ($0.product.name, $0.items.map(\.label)) })
        XCTAssertEqual(byName["Docker"], ["com.docker.helper", "com.docker.socket"])
        XCTAssertEqual(byName["Google Software Update (Keystone)"], ["com.google.keystone.agent"])
        XCTAssertEqual(byName["Example"], ["com.example.sync", "com.example.updater"])
        XCTAssertEqual(byName["loose-label"], ["loose-label"])
        XCTAssertEqual(groups.count, 4)
    }

    func testAssociatedBundleIDWithoutInstalledAppStillGroupsByThatApp() {
        let product = StartupProductAttribution.product(
            for: agent("com.acme.helper", associated: ["com.acme.suite"]))
        XCTAssertEqual(product.key, "app:com.acme.suite")
        XCTAssertEqual(product.name, "Acme")
    }

    func testVendorHeuristicSkipsTeamIDPrefixAndApple() {
        XCTAssertEqual(StartupProductAttribution.vendor(fromReverseDNS: "2BUA8C4S2C.com.1password.helper"), "1password")
        XCTAssertNil(StartupProductAttribution.vendor(fromReverseDNS: "com.apple.something"))
        XCTAssertNil(StartupProductAttribution.vendor(fromReverseDNS: "plain"))
    }
}

final class NewStartupItemsRuleTests: XCTestCase {
    private let rule = NewStartupItemsRule()

    private func finding(labels: [String]) -> Finding {
        StartupWatch.finding(
            for: NewStartupItems(product: StartupProduct(key: "app:com.docker.docker", name: "Docker"),
                                 items: labels.map { agent($0) }),
            at: fixtureDate)
    }

    func testOneSuggestionPerProductOpeningTheReviewRoute() throws {
        let finding = finding(labels: ["com.docker.helper", "com.docker.socket"])
        XCTAssertEqual(finding.key, SuggestionKey(moduleID: "bootcaptain",
                                                  condition: "new-startup-items:app:com.docker.docker",
                                                  scope: .local))

        let content = try XCTUnwrap(rule.suggestion(for: finding, state: .inactive))
        XCTAssertEqual(content.title, "Docker installed 2 new startup items")
        XCTAssertTrue(content.detail.contains("com.docker.helper, com.docker.socket"))
        XCTAssertEqual(content.route, ModuleRoute(moduleID: "bootcaptain", action: "review"))
    }

    func testSingularWording() throws {
        let content = try XCTUnwrap(rule.suggestion(for: finding(labels: ["com.docker.helper"]),
                                                    state: .inactive))
        XCTAssertEqual(content.title, "Docker installed 1 new startup item")
        XCTAssertTrue(content.detail.hasPrefix("It is not in the list"))
    }

    func testLongListsNameOnlyTheFirstFew() {
        let finding = finding(labels: ["a.b.1", "a.b.2", "a.b.3", "a.b.4", "a.b.5"])
        XCTAssertEqual(finding.text("labels"), "a.b.1, a.b.2, a.b.3 and 2 more")
        XCTAssertEqual(finding.count("count"), 5)
    }

    func testNoSuggestionForZeroOrForeignFindings() {
        let zero = Finding(moduleID: "bootcaptain", condition: "new-startup-items:x", observedAt: fixtureDate,
                           evidence: ["count": .count(0)])
        XCTAssertNil(rule.suggestion(for: zero, state: .active))

        let foreign = Finding(moduleID: "dockvac", condition: "new-startup-items:x", observedAt: fixtureDate,
                              evidence: ["count": .count(3)])
        XCTAssertNil(rule.suggestion(for: foreign, state: .inactive))
    }

    func testRouteIsAcceptedByTheProvidersAllowlist() throws {
        let content = try XCTUnwrap(rule.suggestion(for: finding(labels: ["x.y.z"]), state: .inactive))
        let allowlist = RouteAllowlist(modules: ["bootcaptain"],
                                       actions: ["bootcaptain": [StartupWatch.reviewAction: []]])
        XCTAssertNoThrow(try allowlist.validate(content.route))
        XCTAssertEqual(try allowlist.route(from: content.route.url), content.route)
    }
}
