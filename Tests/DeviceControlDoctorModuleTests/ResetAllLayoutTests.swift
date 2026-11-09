import AppKit
import DoctorCore
import SwiftUI
import XCTest
@testable import DeviceControlDoctorModule

@MainActor
final class ResetAllLayoutTests: XCTestCase {
    func testHundredsOfAffectedProcessesDoNotGrowTheConfirmationOffScreen() async throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        let runner = listedClients(count: 250)
        let lifecycle = LayoutLifecycle(processCount: 200)
        let store = makeStore(mac: mac, runner: runner, lifecycle: lifecycle)
        let probe = LayoutProbe(root: ResetAllView().environmentObject(store))
        defer { probe.close() }

        try await waitForInspection(lifecycle)

        let size = probe.fittingSize()
        XCTAssertLessThanOrEqual(size.height, 620,
                                 "the process table must scroll instead of increasing the sheet height")
        XCTAssertLessThanOrEqual(size.width, 860)
        try probe.scrollReviewToBottom()
        XCTAssertEqual(probe.fittingSize(), size, "scrolling must not resize the confirmation")
        XCTAssertFalse(runner.ranReset, "opening and reviewing the sheet must never reset permissions")
        XCTAssertEqual(lifecycle.terminationRequests, 0)
    }

    func testConfirmationWithNoRunningProcessesFitsWithoutMutating() async throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        let runner = listedClients(count: 2)
        let lifecycle = LayoutLifecycle(processCount: 0)
        let store = makeStore(mac: mac, runner: runner, lifecycle: lifecycle)
        let probe = LayoutProbe(root: ResetAllView().environmentObject(store))
        defer { probe.close() }

        try await waitForInspection(lifecycle)

        XCTAssertLessThanOrEqual(probe.fittingSize().height, 620)
        XCTAssertLessThanOrEqual(probe.fittingSize().width, 860)
        XCTAssertFalse(runner.ranReset)
        XCTAssertEqual(lifecycle.terminationRequests, 0)
    }

    func testUnavailableInspectionFitsWithoutMutating() async throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        let runner = FakeProcessRunner()
        runner.withholdListing()
        let lifecycle = LayoutLifecycle(processCount: 0)
        let store = makeStore(mac: mac, runner: runner, lifecycle: lifecycle)
        let probe = LayoutProbe(root: ResetAllView().environmentObject(store))
        defer { probe.close() }
        let deadline = Date().addingTimeInterval(5)
        while store.notice == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertNotNil(store.notice)
        XCTAssertLessThanOrEqual(probe.fittingSize().height, 620)
        XCTAssertLessThanOrEqual(probe.fittingSize().width, 860)
        XCTAssertFalse(runner.ranReset)
        XCTAssertEqual(lifecycle.inspections, 0)
        XCTAssertEqual(lifecycle.terminationRequests, 0)
    }

    func testMainPaneFitsMinimumWindowWithoutAWatchListSelection() async throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        let runner = FakeProcessRunner()
        runner.withholdListing()
        let store = makeStore(mac: mac, runner: runner, lifecycle: LayoutLifecycle(processCount: 0))
        let probe = LayoutProbe(root: MainView(route: nil).environmentObject(store),
                                size: NSSize(width: 980, height: 650))
        defer { probe.close() }
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(store.selectedApp)
        XCTAssertLessThanOrEqual(probe.fittingSize().height, 650)
        XCTAssertLessThanOrEqual(probe.fittingSize().width, 980)
        XCTAssertFalse(runner.ranReset)
    }

    func testPerAppRecordingRepairScrollsWithoutGrowingOrResetting() async throws {
        let mac = try FixtureMac()
        defer { mac.remove() }
        let runner = FakeProcessRunner()
        let store = makeStore(mac: mac, runner: runner, lifecycle: LayoutLifecycle(processCount: 0))
        let app = WatchedApp(name: "Teams", bundleID: "com.microsoft.teams2",
                             path: "/Applications/" + String(repeating: "Long folder/", count: 250) + "Teams.app", version: "1")
        let probe = LayoutProbe(root: RepairView(app: app).environmentObject(store),
                                size: NSSize(width: 620, height: 620))
        defer { probe.close() }
        try await Task.sleep(nanoseconds: 50_000_000)

        let size = probe.fittingSize()
        XCTAssertLessThanOrEqual(size.height, 620)
        XCTAssertLessThanOrEqual(size.width, 620)
        try probe.scrollReviewToBottom()
        XCTAssertEqual(probe.fittingSize(), size)
        XCTAssertTrue(runner.calls.isEmpty, "opening the dialog must neither query nor reset permissions")
    }

    private func makeStore(mac: FixtureMac, runner: FakeProcessRunner,
                           lifecycle: LayoutLifecycle) -> DoctorStore {
        let defaults = UserDefaults(suiteName: "ResetAllLayoutTests.\(UUID().uuidString)")!
        return DoctorStore(defaults: defaults, runner: runner, storageURL: mac.watchList,
                           lifecycle: lifecycle, settingsOpener: { _ in })
    }

    private func listedClients(count: Int) -> FakeProcessRunner {
        let runner = FakeProcessRunner()
        runner.offerListing()
        let clients = (0..<count).map { "com.example.Client\($0)" }.joined(separator: "\n")
        for service in GlobalRepairPlan().services {
            runner.respond(to: [SystemTool.tccutil, "list", "-s", service.rawValue],
                           with: CommandResult(output: clients, exitCode: 0))
        }
        return runner
    }

    private func waitForInspection(_ lifecycle: LayoutLifecycle) async throws {
        let deadline = Date().addingTimeInterval(5)
        while lifecycle.inspections == 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertGreaterThan(lifecycle.inspections, 0, "the fixture inspection must finish before measuring")
        // Let SwiftUI apply the preparation returned by the async inspection.
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    /// Keep native view lifetime out of the async test's frame.
    @MainActor
    private final class LayoutProbe {
        private let host: NSView
        private let window: NSWindow

        init<Content: View>(root: Content, size: NSSize = NSSize(width: 860, height: 620)) {
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .resizable],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            self.host = host
            self.window = window
        }

        func fittingSize() -> NSSize {
            host.layoutSubtreeIfNeeded()
            return host.fittingSize
        }

        func scrollReviewToBottom() throws {
            let scroll = try XCTUnwrap(descendants(of: host).compactMap { $0 as? NSScrollView }.first)
            let document = try XCTUnwrap(scroll.documentView)
            XCTAssertGreaterThan(document.frame.height, scroll.contentView.bounds.height,
                                 "the long process list must overflow inside a scroll view")
            scroll.contentView.scroll(to: NSPoint(x: 0, y: document.frame.height - scroll.contentView.bounds.height))
            scroll.reflectScrolledClipView(scroll.contentView)
            XCTAssertEqual(scroll.contentView.bounds.maxY, document.frame.height, accuracy: 1,
                           "the end of the review must remain reachable")
        }

        func close() {
            window.close()
        }

        private func descendants(of view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants(of: $0) }
        }
    }
}

@MainActor
private final class LayoutLifecycle: ApplicationLifecycleManaging {
    var inspections = 0
    var terminationRequests = 0
    private let processCount: Int

    init(processCount: Int) {
        self.processCount = processCount
    }

    func runningProcesses(matching clients: Set<String>) async throws -> [AffectedProcess] {
        inspections += 1
        return (0..<processCount).map { index in
            AffectedProcess(processIdentifier: Int32(90_000 + index), name: "Fixture app \(index)",
                            executablePath: "/fixture/app-\(index)", canRequestTermination: true)
        }
    }

    func requestTermination(of processes: [AffectedProcess]) {
        terminationRequests += 1
    }
}
