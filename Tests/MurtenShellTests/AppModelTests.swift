import XCTest
import SwiftUI
import MurtenCore
import MurtenModuleKit
@testable import MurtenShell

@MainActor
final class AppModelTests: XCTestCase {
    private func residentSettings(notifying: Set<String> = []) -> SuiteSettings {
        var settings = SuiteSettings()
        settings.residentMode = .on
        settings.notifyingModules = notifying
        return settings
    }

    // MARK: - Opt-in

    func testNothingRunsUntilResidentModeIsOn() async {
        let harness = Harness()
        await harness.model.start()
        harness.clock.advance(by: WatchSchedule.initialDelay)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(harness.model.suggestions.isEmpty)
        XCTAssertEqual(harness.settings.stored.residentMode, .off)
        await harness.model.stop()
    }

    func testResidentWatcherFeedsTheSuggestionFeed() async {
        let harness = Harness(settings: residentSettings())
        await harness.model.start()
        harness.clock.advance(by: WatchSchedule.initialDelay)

        let surfaced = await eventually { harness.model.suggestions.count == 1 }
        XCTAssertTrue(surfaced)
        XCTAssertEqual(harness.model.suggestions.first?.route, ModuleRoute(moduleID: fakeModuleID, action: "reclaim"))
        XCTAssertTrue(harness.notifier.delivered.isEmpty, "notifications are opt-in per module")
        await harness.model.stop()
    }

    func testOptedInModuleNotifiesOncePerEpisode() async {
        let harness = Harness(settings: residentSettings(notifying: [fakeModuleID]))
        await harness.model.start()
        harness.clock.advance(by: WatchSchedule.initialDelay)
        _ = await eventually { harness.model.suggestions.count == 1 }

        harness.clock.advance(by: 30 * 60)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(harness.notifier.delivered.count, 1)
        await harness.model.stop()
    }

    func testTurningResidentModeOffHidesSuggestionsAndStopsChecks() async {
        let harness = Harness(settings: residentSettings())
        await harness.model.start()
        harness.clock.advance(by: WatchSchedule.initialDelay)
        _ = await eventually { harness.model.suggestions.count == 1 }

        harness.model.settings.residentMode = .off
        let hidden = await eventually { harness.model.suggestions.isEmpty }
        XCTAssertTrue(hidden)
        XCTAssertEqual(harness.settings.stored.residentMode, .off, "settings persist on change")
        await harness.model.stop()
    }

    func testInapplicableModuleNeverWatchesNorOpens() async {
        let harness = Harness(settings: residentSettings(), applicability: .inapplicable(reason: "Docker is not installed"))
        await harness.model.start()
        harness.clock.advance(by: WatchSchedule.initialDelay)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(harness.model.suggestions.isEmpty)
        XCTAssertEqual(harness.model.open(ModuleRoute(moduleID: fakeModuleID)), .rejected("Docker is not installed"))
        XCTAssertNil(harness.model.openRoute)
        await harness.model.stop()
    }

    // MARK: - Routing

    func testSuggestionOpensItsPaneWithTheRoute() async {
        let harness = Harness(settings: residentSettings())
        await harness.model.start()
        harness.clock.advance(by: WatchSchedule.initialDelay)
        _ = await eventually { harness.model.suggestions.count == 1 }
        let suggestion = try! XCTUnwrap(harness.model.suggestions.first)

        XCTAssertEqual(harness.model.open(suggestion.route), .opened)
        XCTAssertEqual(harness.model.openRoute, suggestion.route)
        XCTAssertNotNil(harness.model.pane(for: suggestion.route))
        XCTAssertEqual(harness.provider.panesMade.last, suggestion.route)

        harness.model.openHome()
        XCTAssertNil(harness.model.openRoute)
        XCTAssertEqual(harness.model.lastOpenedModuleID, fakeModuleID, "focus returns to the originating tile")
        await harness.model.stop()
    }

    func testRejectsRoutesOutsideTheAllowlist() async {
        let harness = Harness()
        await harness.model.start()

        guard case .rejected = harness.model.open(ModuleRoute(moduleID: fakeModuleID, action: "prune-all")) else {
            return XCTFail("unknown action must be rejected")
        }
        guard case .rejected = harness.model.open(ModuleRoute(moduleID: "repomen")) else {
            return XCTFail("planned modules must not open")
        }
        XCTAssertNil(harness.model.openRoute)
    }

    func testNotificationURLIsValidatedBeforeOpening() async {
        let harness = Harness()
        await harness.model.start()

        harness.notifier.onOpen?(URL(string: "murten://dockvac/reclaim?command=rm")!)
        XCTAssertNil(harness.model.openRoute)
        XCTAssertFalse(harness.model.diagnostics.isEmpty)

        harness.notifier.onOpen?(URL(string: "murten://dockvac/reclaim?endpoint=local")!)
        XCTAssertEqual(harness.model.openRoute?.context, ["endpoint": "local"])
        XCTAssertGreaterThan(harness.model.windowRequests, 0)
    }

    func testModuleContextOpensRoutesThroughTheModel() async {
        let harness = Harness()
        await harness.model.start()

        harness.provider.context.open(ModuleRoute(moduleID: fakeModuleID))
        XCTAssertEqual(harness.model.openRoute, ModuleRoute(moduleID: fakeModuleID))
    }

    // MARK: - Snooze, dismiss

    func testSnoozeAndDismissRemoveTheSuggestionFromTheFeed() async {
        let harness = Harness(settings: residentSettings())
        await harness.model.start()
        harness.clock.advance(by: WatchSchedule.initialDelay)
        _ = await eventually { harness.model.suggestions.count == 1 }
        let suggestion = harness.model.suggestions[0]

        await harness.model.snooze(suggestion, for: .oneDay)
        let snoozed = await eventually { harness.model.suggestions.isEmpty }
        XCTAssertTrue(snoozed)

        harness.clock.advance(by: SnoozeDuration.oneDay.interval)
        await harness.model.refreshFeed()
        XCTAssertEqual(harness.model.suggestions.count, 1, "a snooze ends at its deadline")

        await harness.model.dismiss(harness.model.suggestions[0])
        let dismissed = await eventually { harness.model.suggestions.isEmpty }
        XCTAssertTrue(dismissed)
        await harness.model.stop()
    }

    // MARK: - Settings intents

    func testNotificationsNeedAuthorization() async {
        let harness = Harness()
        harness.notifier.authorization = .denied
        await harness.model.setNotifications(.on, for: fakeModuleID)
        XCTAssertTrue(harness.model.settings.notifyingModules.isEmpty)
        XCTAssertEqual(harness.model.notificationAuthorization, .denied)

        harness.notifier.authorization = .granted
        await harness.model.setNotifications(.on, for: fakeModuleID)
        XCTAssertEqual(harness.model.settings.notifyingModules, [fakeModuleID])
    }

    func testLaunchAtLoginFollowsTheSystemStatus() async {
        let harness = Harness()
        await harness.model.start()
        harness.model.setLaunchAtLogin(.register)
        XCTAssertEqual(harness.model.launchAtLogin, .enabled)
        harness.model.setLaunchAtLogin(.unregister)
        XCTAssertEqual(harness.model.launchAtLogin, .disabled)
    }

    func testUpdateChecksAreOffByDefaultAndReportNewerReleases() async {
        let quiet = Harness()
        await quiet.model.start()
        XCTAssertNil(quiet.model.availableUpdate)

        var settings = SuiteSettings()
        settings.updateChecks = .daily
        let checking = Harness(settings: settings)
        await checking.model.start()
        XCTAssertEqual(checking.model.availableUpdate?.version, ReleaseVersion("9.9.9"))
    }

    func testQuitGuardListsBusyModules() async {
        let harness = Harness()
        XCTAssertTrue(harness.model.interruptionWarnings().isEmpty)
        harness.provider.busy = "A cleanup is still running."
        XCTAssertEqual(harness.model.interruptionWarnings(), ["DockVac: A cleanup is still running."])
    }

    // MARK: - Views

    func testRootViewRendersHomeAndPane() async {
        let harness = Harness()
        await harness.model.start()

        let host = NSHostingView(rootView: RootView(model: harness.model))
        host.frame = NSRect(x: 0, y: 0, width: 1040, height: 720)
        host.layoutSubtreeIfNeeded()

        harness.model.open(ModuleRoute(moduleID: fakeModuleID))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(harness.model.openRoute?.moduleID, fakeModuleID)
    }
}
