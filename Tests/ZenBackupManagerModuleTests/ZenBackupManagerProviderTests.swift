import AppKit
import SwiftUI
import XCTest
import MurtenCore
import MurtenModuleKit
@testable import ZenBackupManagerCore
@testable import ZenBackupManagerModule

@MainActor
final class ZenBackupManagerProviderTests: XCTestCase {
    private func makeProvider(_ zen: ZenFolder) -> ZenBackupManagerProvider {
        ZenBackupManagerProvider(locations: ZenBackupLocations(zenRoot: zen.root, safetyRoot: zen.safetyRoot))
    }

    /// Waits for the pane's background scan to land.
    private func scanned(_ model: AppModel) async {
        let deadline = Date().addingTimeInterval(5)
        while model.busy && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(model.busy, "scan did not finish")
    }

    // MARK: - Contract

    func testRegistersTheTimelineRouteAndAWatcher() throws {
        let provider = makeProvider(try makeZenFolder())
        XCTAssertEqual(provider.moduleID, "zenbackupmanager")
        XCTAssertEqual(provider.moduleID, ModuleRegistry.all.first { $0.name == "Zen Backup Manager" }?.id)
        XCTAssertEqual(provider.routeActions, ["timeline": ["profile"]])
        XCTAssertEqual(provider.watch?.moduleID, provider.moduleID)
        XCTAssertNotNil(provider.makeSettings())
        XCTAssertNil(provider.makeMenuSection())
        XCTAssertNil(provider.interruptionWarning)
    }

    func testTheRulesRoutePassesTheProvidersAllowlist() throws {
        let zen = try makeZenFolder()
        let provider = makeProvider(zen)
        let profile = ZenProfile(name: "Work", directory: zen.directory("Work"), isDefault: true)
        let finding = SessionStalenessRule.finding(for: profile, newestSnapshot: Date(timeIntervalSince1970: 0), observedAt: Date())
        let route = try XCTUnwrap(provider.watch?.rule.suggestion(for: finding, state: .inactive)?.route)

        let allowlist = RouteAllowlist(modules: [provider.moduleID], actions: [provider.moduleID: provider.routeActions])
        XCTAssertEqual(try allowlist.validate(route), route)
    }

    func testWithoutAZenProfileTheModuleIsInapplicable() async throws {
        let zen = try makeZenFolder()
        let empty = await makeProvider(zen).applicability()
        XCTAssertEqual(empty, .inapplicable(reason: "Zen Browser is not installed"))

        try zen.list(["Work"])
        let listed = await makeProvider(zen).applicability()
        XCTAssertEqual(listed, .applicable)
    }

    func testAnUnreadableProfileListSaysSo() async throws {
        let zen = try makeZenFolder()
        try FileManager.default.createDirectory(at: zen.root.appendingPathComponent("profiles.ini"), withIntermediateDirectories: true)
        guard case .inapplicable(let reason) = await makeProvider(zen).applicability() else {
            return XCTFail("an unreadable profile list must not count as installed")
        }
        XCTAssertTrue(reason.hasPrefix("Zen's profile list could not be read"), reason)
    }

    // MARK: - Pane

    func testATileClickSelectsTheNewestRestorableBackupAsBefore() async throws {
        let zen = try makeZenFolder()
        try zen.list(["Work"])
        try zen.snapshot("Work", at: "zen-sessions.jsonlz4", tabs: ["https://swift.org"], daysAgo: 0)
        try zen.snapshot("Work", at: "zen-sessions-backup/zen-sessions-a.jsonlz4", tabs: ["https://old.example"], daysAgo: 2)
        let model = makeProvider(zen).model

        model.appear(for: ModuleRoute(moduleID: "zenbackupmanager"))
        await scanned(model)

        XCTAssertEqual(model.records.count, 2)
        XCTAssertEqual(model.selected?.kind, .automatic)
        XCTAssertEqual(model.selected?.canRestore, true)
    }

    func testASuggestionOpensItsProfileRescansAndPreselectsNoBackup() async throws {
        let zen = try makeZenFolder()
        try zen.list(["Work", "Home"])
        try zen.snapshot("Home", at: "zen-sessions.jsonlz4", tabs: ["https://swift.org"], daysAgo: 9)
        try zen.snapshot("Home", at: "zen-sessions-backup/zen-sessions-a.jsonlz4", tabs: ["https://old.example"], daysAgo: 10)
        let model = makeProvider(zen).model

        model.appear(for: ModuleRoute(moduleID: "zenbackupmanager"))
        await scanned(model)
        XCTAssertEqual(model.profile?.name, "Work", "the default profile opens first")

        let home = try zen.profile("Home")
        try zen.snapshot("Home", at: "zen-sessions-backup/zen-sessions-b.jsonlz4", tabs: ["https://new.example"], daysAgo: 9.5)
        model.appear(for: ModuleRoute(moduleID: "zenbackupmanager", action: "timeline", context: ["profile": home.id]))
        await scanned(model)

        XCTAssertEqual(model.profileID, home.id)
        XCTAssertEqual(model.records.count, 3, "the pane re-scans")
        XCTAssertEqual(model.selected?.kind, .current)
        XCTAssertNotEqual(model.selected?.canRestore, true, "a suggestion never preselects a backup to restore")
    }

    func testAFailedDiscoveryIsRetriedOnTheNextVisit() async throws {
        let zen = try makeZenFolder()
        let unreadable = zen.root.appendingPathComponent("profiles.ini")
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        let model = makeProvider(zen).model

        model.appear(for: ModuleRoute(moduleID: "zenbackupmanager"))
        XCTAssertNotNil(model.error)
        XCTAssertTrue(model.profiles.isEmpty)

        try FileManager.default.removeItem(at: unreadable)
        try zen.list(["Work"])
        model.error = nil
        model.appear(for: ModuleRoute(moduleID: "zenbackupmanager"))
        await scanned(model)

        XCTAssertNil(model.error)
        XCTAssertEqual(model.profile?.name, "Work", "the suite outlives one launch, so a plain visit discovers again")
    }

    func testAPlainRevisitKeepsThePanesState() async throws {
        let zen = try makeZenFolder()
        try zen.list(["Work"])
        try zen.snapshot("Work", at: "zen-sessions.jsonlz4", daysAgo: 0)
        let model = makeProvider(zen).model
        model.appear(for: ModuleRoute(moduleID: "zenbackupmanager"))
        await scanned(model)

        try zen.snapshot("Work", at: "zen-sessions-backup/zen-sessions-a.jsonlz4", daysAgo: 1)
        model.appear(for: ModuleRoute(moduleID: "zenbackupmanager"))

        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.records.count, 1)
    }

    func testThePaneRendersInAHostingView() throws {
        let zen = try makeZenFolder()
        try zen.list(["Work"])
        let provider = makeProvider(zen)
        let host = NSHostingView(rootView: provider.makePane(route: ModuleRoute(moduleID: "zenbackupmanager")))
        host.frame = NSRect(x: 0, y: 0, width: 1040, height: 720)
        host.layoutSubtreeIfNeeded()
    }
}
