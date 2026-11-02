import XCTest
import MurtenCore
import ObtainintoshCore
@testable import ObtainintoshServices

/// The background check against fixture observers, never the live system.
final class ObtainintoshWatcherTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Answers from fixtures and counts what it was asked.
    private final class FixtureObserver: UpdateObserving, @unchecked Sendable {
        var list: Result<TrackedAppData?, Error>
        var installed: [String: InstalledVersion] = [:]
        var releases: [String: Result<Release, Error>] = [:]
        var allowance = 20
        private let lock = NSLock()
        private var asked: [String] = []

        init(_ list: Result<TrackedAppData?, Error>) {
            self.list = list
        }

        var lookups: [String] { lock.withLock { asked } }

        func trackedList() throws -> TrackedAppData? { try list.get() }

        func installedVersions(of apps: [TrackedApp]) async -> [InstalledVersion?] {
            apps.map { installed[$0.id] }
        }

        func gitHubAllowance() async -> Int { allowance }

        func latestRelease(of app: TrackedApp, budget: RequestBudget) async throws -> Release {
            lock.withLock { asked.append(app.id) }
            try await budget.spend()
            guard let result = releases[app.id] else { throw LookupFailure(.failed, "no fixture") }
            return try result.get()
        }
    }

    private func app(_ id: String, _ type: SourceType = .github) -> TrackedApp {
        TrackedApp(id: id, name: id.capitalized, sourceType: type, sourceURL: "https://github.com/o/\(id)")
    }

    private func release(_ version: String) -> Result<Release, Error> {
        .success(Release(version: version, downloadURL: "u", fileName: "f.dmg", fileSize: 1))
    }

    private func observe(_ observer: FixtureObserver) async -> WatchObservation {
        await ObtainintoshWatcher(observer: observer, now: { [now] in now }).observe()
    }

    func testCadenceIsSlowAndDeclaresTheNetwork() {
        let watcher = ObtainintoshWatcher(observer: FixtureObserver(.success(nil)))
        XCTAssertGreaterThanOrEqual(watcher.cadence.interval, 6 * 3600)
        XCTAssertTrue(watcher.cadence.resources.contains(.network))
        XCTAssertEqual(watcher.moduleID, "obtainintosh")
    }

    func testNoListIsACompleteCheckOfNothing() async {
        let observation = await observe(FixtureObserver(.success(nil)))
        XCTAssertEqual(observation.outcome, .complete)
        XCTAssertTrue(observation.findings.isEmpty)
    }

    func testAnUnreadableListMakesTheCheckUnavailable() async {
        let observation = await observe(FixtureObserver(.failure(ObtainintoshError("corrupt"))))
        XCTAssertEqual(observation.outcome, .unavailable)
        XCTAssertEqual(observation.failures.first?.kind, .malformedResponse)
    }

    func testInstalledProgramsAreLookedUpAndOthersCostNothing() async {
        let observer = FixtureObserver(.success(TrackedAppData(apps: [app("tool"), app("absent")],
                                                               removedAppIDs: ["gone"])))
        observer.installed["tool"] = InstalledVersion(path: "/Applications/Tool.app", version: "1.0")
        observer.releases["tool"] = release("1.1")

        let observation = await observe(observer)

        XCTAssertEqual(observer.lookups, ["tool"])
        XCTAssertEqual(observation.outcome, .complete)
        XCTAssertEqual(observation.completedScopes, [FindingScope("tool"), FindingScope("absent"), FindingScope("gone")])
        XCTAssertEqual(observation.findings.count, 1)
        let finding = observation.findings[0]
        XCTAssertEqual(finding.scope, FindingScope("tool"))
        XCTAssertEqual(finding.observedAt, now)
        XCTAssertEqual(UpdateRule().suggestion(for: finding, state: .inactive)?.title, "Tool 1.1 is available")
    }

    func testFailuresAreReportedPerProgramNotAsNothingFound() async {
        let observer = FixtureObserver(.success(TrackedAppData(apps: [app("ok"), app("offline"), app("private", .forgejo)])))
        for id in ["ok", "offline", "private"] {
            observer.installed[id] = InstalledVersion(path: "/Applications/\(id).app", version: "1.0")
        }
        observer.releases["ok"] = release("1.0")
        observer.releases["offline"] = .failure(LookupFailure(.unreachable, "Failed to fetch GitHub release: offline"))
        observer.releases["private"] = .failure(LookupFailure(.permissionDenied, "key not readable"))

        let observation = await observe(observer)

        XCTAssertEqual(observation.outcome, .partial)
        XCTAssertEqual(observation.completedScopes, [FindingScope("ok")])
        XCTAssertEqual(Set(observation.failures.map(\.scope)), [FindingScope("offline"), FindingScope("private")])
        let kinds = Dictionary(uniqueKeysWithValues: observation.failures.map { ($0.scope!, $0.kind) })
        XCTAssertEqual(kinds[FindingScope("offline")], .unreachable)
        XCTAssertEqual(kinds[FindingScope("private")], .permissionDenied)
        XCTAssertTrue(observation.failures.allSatisfy { $0.message.hasPrefix("Offline:") || $0.message.hasPrefix("Private:") })
    }

    func testAnUnsupportedSourceIsCheckedWithoutASuggestion() async {
        let observer = FixtureObserver(.success(TrackedAppData(apps: [app("lab", .gitlab)])))
        observer.installed["lab"] = InstalledVersion(path: "/Applications/Lab.app", version: "1.0")
        observer.releases["lab"] = .failure(LookupFailure(.unsupported, "GitLab support not yet implemented"))

        let observation = await observe(observer)

        XCTAssertEqual(observation.outcome, .complete)
        XCTAssertEqual(observation.completedScopes, [FindingScope("lab")])
        XCTAssertTrue(observation.findings.isEmpty)
    }

    func testTheGitHubAllowanceLimitsAPoll() async {
        let apps = (1...5).map { app("tool\($0)") }
        let observer = FixtureObserver(.success(TrackedAppData(apps: apps)))
        observer.allowance = 3
        for app in apps {
            observer.installed[app.id] = InstalledVersion(path: "/Applications/\(app.id).app", version: "1.0")
            observer.releases[app.id] = release("1.0")
        }

        let observation = await observe(observer)

        XCTAssertEqual(observation.completedScopes.count, 3)
        XCTAssertEqual(observation.failures.count, 2)
        XCTAssertTrue(observation.failures.allSatisfy { $0.message.contains("request limit") })
    }

    func testARemovedProgramsSuggestionResolves() async {
        var ledger = SuggestionLedger()
        let observer = FixtureObserver(.success(TrackedAppData(apps: [app("tool")])))
        observer.installed["tool"] = InstalledVersion(path: "/Applications/Tool.app", version: "1.0")
        observer.releases["tool"] = release("2.0")
        ledger.apply(await observe(observer), rule: UpdateRule())
        XCTAssertEqual(ledger.suggestions(at: now).count, 1)

        observer.list = .success(TrackedAppData(apps: [], removedAppIDs: ["tool"]))
        ledger.apply(await observe(observer), rule: UpdateRule())

        XCTAssertTrue(ledger.suggestions(at: now).isEmpty)
    }

    // MARK: - The live observer's credentials

    func testTheLiveObserverNeverReadsTheKeychain() async throws {
        let store = MemorySecretStore(["forgejo-key.private": "key123", "github-token": "ghp"])
        let vault = CredentialVault(store: store)
        let transport = FakeTransport([.json(200, #"{"tag_name": "v1.0", "assets": [{"name": "Tool.dmg", "size": 1, "browser_download_url": "u"}]}"#)])
        let observer = LiveUpdateObserver(listURL: URL(fileURLWithPath: "/nonexistent/apps.json"),
                                          detector: InstalledVersionDetector(applicationFolders: [], fontFolders: []),
                                          lookup: ReleaseLookup(transport: transport), vault: vault)
        let budget = GitHubRateBudget(maximumRequests: 5)
        var privateApp = TrackedApp(id: "private", name: "Private", sourceType: .forgejo,
                                    sourceURL: "https://codeberg.org/o/private", username: "alice")
        privateApp.hasStoredAccessToken = true

        do {
            _ = try await observer.latestRelease(of: privateApp, budget: budget)
            XCTFail("checked without the key")
        } catch {
            XCTAssertEqual((error as? LookupFailure)?.kind, .permissionDenied)
        }
        // GitHub without a token in memory goes out unauthenticated.
        _ = try await observer.latestRelease(of: app("tool"), budget: budget)
        XCTAssertNil(transport.requests.last?.authorization)
        let allowance = await observer.gitHubAllowance()
        XCTAssertEqual(allowance, GitHubRateBudget.unauthenticatedAllowance)
        XCTAssertEqual(store.reads, 0, "the background check read the Keychain")
        XCTAssertNil(try observer.trackedList())
    }

    func testTheLiveObserverUsesKeysThePaneAlreadyRead() async throws {
        let vault = CredentialVault(store: MemorySecretStore(["forgejo-key.private": "key123"]))
        _ = try await vault.token(.forgejo(appID: "private"))
        let transport = FakeTransport([.json(200, #"{"tag_name": "v1.0", "assets": [{"name": "Tool-macos.dmg", "size": 1, "browser_download_url": "u"}]}"#)])
        let observer = LiveUpdateObserver(listURL: URL(fileURLWithPath: "/nonexistent/apps.json"),
                                          detector: InstalledVersionDetector(applicationFolders: [], fontFolders: []),
                                          lookup: ReleaseLookup(transport: transport), vault: vault)
        var privateApp = TrackedApp(id: "private", name: "Private", sourceType: .forgejo,
                                    sourceURL: "https://codeberg.org/o/private")
        privateApp.hasStoredAccessToken = true

        let release = try await observer.latestRelease(of: privateApp, budget: GitHubRateBudget(maximumRequests: 1))

        XCTAssertEqual(release.version, "1.0")
        XCTAssertEqual(transport.requests.first?.authorization, "token key123")
    }

    func testTheLiveObserverReadsFontsWhereThePaneFoundThem() async {
        let fonts = ScratchDirectory("watcher-fonts")
        let font = fonts.write(TestFonts.font(declaring: "1.2"), to: "Inter.ttf")
        let observer = LiveUpdateObserver(listURL: URL(fileURLWithPath: "/nonexistent/apps.json"),
                                          detector: InstalledVersionDetector(applicationFolders: [], fontFolders: []),
                                          lookup: ReleaseLookup(transport: FakeTransport([])),
                                          vault: CredentialVault(store: MemorySecretStore()))
        var tracked = app("inter")
        tracked.installPath = font.path

        let installed = await observer.installedVersions(of: [tracked, app("absent")])

        XCTAssertEqual(installed, [InstalledVersion(path: font.path, version: "1.2"), nil])
    }
}
