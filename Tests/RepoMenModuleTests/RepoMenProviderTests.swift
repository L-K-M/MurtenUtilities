import XCTest
import MurtenCore
import MurtenModuleKit
@testable import RepoMenModule
@testable import RepoMenCore

/// The provider as the suite sees it: its watcher registration, its routes, and
/// what opening a route does. Scans run against temp folders only.
@MainActor
final class RepoMenProviderTests: XCTestCase {

    private struct NoSurvey: StaleArtifactObserving {
        func survey(_ settings: StaleWatchSettings, now: Date) async -> [String: WatchRootStatus]? { [:] }
    }

    private final class Counter: @unchecked Sendable {
        var value = 0
    }

    private func makeProvider(recheck: Counter = Counter()) -> RepoMenProvider {
        let name = "RepoMenProviderTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        // No default scan roots and only project rules: a scan here must never
        // walk the runner's home folder or its caches.
        defaults.set([String](), forKey: "scanRoots")
        defaults.set(ArtifactKind.allCases.filter { $0 != .rustTarget }.map(\.rawValue), forKey: "disabledKinds")
        let context = ModuleContext(moduleID: "repomen", defaults: defaults,
                                    requestRecheck: { recheck.value += 1 }, open: { _ in })
        return RepoMenProvider(context: context, standaloneValues: nil, observer: NoSurvey(),
                               startsAutoTrash: false)
    }

    private func makeProject(daysAgo: Double = 40) throws -> URL {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("RepoMenProviderTests-\(UUID().uuidString)")
        addTeardownBlock { try? fm.removeItem(at: base) }
        try fm.createDirectory(at: base.appendingPathComponent("app/target"), withIntermediateDirectories: true)
        try Data("[package]".utf8).write(to: base.appendingPathComponent("app/Cargo.toml"))
        return URL(fileURLWithPath: try base.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath ?? base.path)
    }

    private func eventually(timeout: TimeInterval = 10, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    func testRegistersTheBackgroundCheckAndItsRule() {
        let provider = makeProvider()
        XCTAssertEqual(provider.moduleID, ModuleRegistry.all.first { $0.id == "repomen" }?.id)
        XCTAssertEqual(provider.watch?.moduleID, "repomen")
        XCTAssertEqual(provider.watch?.watcher.cadence.interval, 6 * 3600)
        XCTAssertNotNil(provider.makeSettings())
        XCTAssertNotNil(provider.makeMenuSection())
        XCTAssertNil(provider.interruptionWarning)
    }

    func testOnlyReviewAndLogRoutesPassTheAllowlist() throws {
        let provider = makeProvider()
        let allowlist = RouteAllowlist(modules: ["repomen"], actions: ["repomen": provider.routeActions])

        let review = RepoMenRoutes.review(folder: "/Users/test/dev")
        XCTAssertEqual(try allowlist.validate(review), review)
        let log = ModuleRoute(moduleID: "repomen", action: "auto-trash-log")
        XCTAssertEqual(try allowlist.validate(log), log)
        XCTAssertThrowsError(try allowlist.validate(ModuleRoute(moduleID: "repomen", action: "reclaim")))
        XCTAssertThrowsError(try allowlist.validate(ModuleRoute(moduleID: "repomen", action: "review",
                                                                context: ["path": "/"])))
    }

    func testReviewRouteRescansTheWatchedFolderAndChecksNothing() async throws {
        let provider = makeProvider()
        let project = try makeProject()
        provider.preferences.watchedFolders = [WatchedFolder(path: project.path)]

        provider.model.handleOpen(RepoMenRoutes.review(folder: project.path))

        let finished = await eventually { provider.model.phase == .ready }
        XCTAssertTrue(finished)
        XCTAssertEqual(provider.model.items.map(\.path), [project.appendingPathComponent("app/target").path])
        XCTAssertTrue(provider.model.checkedIDs.isEmpty, "a suggestion never preselects (docs/modules.md)")
        XCTAssertEqual(provider.model.sidebarSelection, .all)
    }

    func testReviewRouteIgnoresFoldersTheUserDoesNotWatch() async throws {
        let provider = makeProvider()
        let project = try makeProject()

        provider.model.handleOpen(RepoMenRoutes.review(folder: project.path))

        let finished = await eventually { provider.model.phase != .scanning && provider.model.phase != .measuring }
        XCTAssertTrue(finished)
        XCTAssertTrue(provider.model.items.isEmpty, "a route cannot point a scan anywhere it likes")
    }

    func testPlainOpenScansOnlyWhenTheUserAskedFor() {
        let provider = makeProvider()
        provider.model.handleOpen(nil)
        XCTAssertEqual(provider.model.phase, .idle)

        provider.model.handleOpen(ModuleRoute(moduleID: "repomen", action: "auto-trash-log"))
        XCTAssertEqual(provider.model.sidebarSelection, .autoTrashLog)
    }

    func testChangingWatchedFoldersRequestsARecheck() async {
        let recheck = Counter()
        let provider = makeProvider(recheck: recheck)

        provider.preferences.watchFolder(path: "/Users/test/dev")

        let requested = await eventually { recheck.value > 0 }
        XCTAssertTrue(requested)
    }
}
