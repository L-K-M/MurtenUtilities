import XCTest
@testable import RepoMenCore

/// The survey the background check and auto-trash share, against a synthetic
/// tree in a temp directory, never the real home folder.
final class StaleArtifactSurveyTests: XCTestCase {

    private var root: URL!
    private let fileManager = FileManager.default
    private let now = Date()

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("StaleArtifactSurvey-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        if let path = try root.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath {
            root = URL(fileURLWithPath: path)
        }
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
    }

    private func path(_ relative: String) -> String {
        root.appendingPathComponent(relative).path
    }

    /// A project with an anchor and one artifact whose content was last touched
    /// `daysAgo` days ago.
    private func makeArtifact(project: String, anchor: String, artifact: String, daysAgo: Double) throws {
        let projectURL = root.appendingPathComponent(project)
        let artifactURL = projectURL.appendingPathComponent(artifact)
        try fileManager.createDirectory(at: artifactURL.appendingPathComponent("out"),
                                        withIntermediateDirectories: true)
        try Data("anchor".utf8).write(to: projectURL.appendingPathComponent(anchor))
        try Data(repeating: 7, count: 64 * 1024).write(to: artifactURL.appendingPathComponent("out/blob.bin"))
        let date = now.addingTimeInterval(-daysAgo * 86_400)
        for url in [artifactURL.appendingPathComponent("out/blob.bin"),
                    artifactURL.appendingPathComponent("out"), artifactURL] {
            try fileManager.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
    }

    private func staleItems(_ folders: [WatchedFolder], protectedRoots: [String] = [])
        async -> [String: [CleanableItem]]? {
        await StaleArtifactSurvey.staleItems(
            in: folders, governedBy: folders, excludedPaths: [],
            enabledKinds: Set(ArtifactKind.allCases), protectedRoots: protectedRoots, now: now)
    }

    func testGroupsStaleItemsByTheirGoverningFolder() async throws {
        try makeArtifact(project: "dev/old", anchor: "Cargo.toml", artifact: "target", daysAgo: 40)
        try makeArtifact(project: "dev/fresh", anchor: "Cargo.toml", artifact: "target", daysAgo: 1)
        try makeArtifact(project: "dev/nested/web", anchor: "package.json", artifact: "node_modules", daysAgo: 20)
        let dev = WatchedFolder(path: path("dev"), maxIdleDays: 30)
        let nested = WatchedFolder(path: path("dev/nested"), maxIdleDays: 10)

        let survey = await staleItems([dev, nested])
        let stale = try XCTUnwrap(survey)

        XCTAssertEqual(stale[dev.path]?.map(\.path), [path("dev/old/target")],
                       "fresh artifacts stay; the nested folder's items are its own")
        XCTAssertEqual(stale[nested.path]?.map(\.path), [path("dev/nested/web/node_modules")],
                       "the deepest watched folder's threshold governs")
        let totals = StaleArtifactSurvey.totals(of: stale[dev.path] ?? [])
        XCTAssertEqual(totals.count, 1)
        XCTAssertGreaterThan(totals.bytes, 0)
    }

    func testNeverEntersAProtectedFolderInsideAScannedRoot() async throws {
        try makeArtifact(project: "home/dev/app", anchor: "Cargo.toml", artifact: "target", daysAgo: 40)
        try makeArtifact(project: "home/Documents/app", anchor: "Cargo.toml", artifact: "target", daysAgo: 40)
        let home = WatchedFolder(path: path("home"))

        let survey = await staleItems([home], protectedRoots: [path("home/Documents")])
        let stale = try XCTUnwrap(survey)

        XCTAssertEqual(stale[home.path]?.map(\.path), [path("home/dev/app/target")])
    }

    func testAdmitsOnlyReadableUnprotectedEnabledFolders() throws {
        try fileManager.createDirectory(at: root.appendingPathComponent("dev"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root.appendingPathComponent("Guarded/code"),
                                        withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: root.appendingPathComponent("linked"),
                                           withDestinationURL: root.appendingPathComponent("Guarded/code"))
        let folders = [
            WatchedFolder(path: path("dev")),
            WatchedFolder(path: path("Guarded/code")),
            WatchedFolder(path: path("linked")),
            WatchedFolder(path: path("gone")),
            WatchedFolder(path: path("paused"), isEnabled: false),
        ]

        let (admitted, refused) = StaleArtifactSurvey.admit(folders, protectedRoots: [path("Guarded")])

        XCTAssertEqual(admitted.map(\.path), [path("dev")])
        XCTAssertEqual(refused[path("Guarded/code")], .protected(root: path("Guarded")))
        XCTAssertEqual(refused[path("linked")], .protected(root: path("Guarded")),
                       "a symbolic link into a protected folder is refused before it is followed")
        XCTAssertEqual(refused[path("gone")], .missing)
        XCTAssertNil(refused[path("paused")], "disabled folders are not surveyed at all")
    }

    func testWorktreeRegistrationsIntoProtectedFoldersAreNotFollowed() throws {
        let project = root.appendingPathComponent("project")
        let worktree = root.appendingPathComponent("Guarded/.hidden/editor")
        let registration = project.appendingPathComponent(".git/worktrees/editor")
        try fileManager.createDirectory(at: registration, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: worktree, withIntermediateDirectories: true)
        try Data("gitdir: \(registration.path)\n".utf8).write(to: worktree.appendingPathComponent(".git"))
        try Data("\(worktree.appendingPathComponent(".git").path)\n".utf8)
            .write(to: registration.appendingPathComponent("gitdir"))
        try Data("../..\n".utf8).write(to: registration.appendingPathComponent("commondir"))

        XCTAssertEqual(GitWorktrees.registeredWorktrees(in: project).map(\.path), [worktree.path],
                       "the fixture is a valid registration")
        let guarded = path("Guarded")
        XCTAssertTrue(GitWorktrees.registeredWorktrees(in: project, isAllowed: {
            !ProtectedLocations.contains($0, roots: [guarded])
        }).isEmpty)
    }
}
