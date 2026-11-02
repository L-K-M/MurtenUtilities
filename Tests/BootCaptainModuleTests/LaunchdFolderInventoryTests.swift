import XCTest
import BootCaptainCore
@testable import BootCaptainModule

/// Reads a fixture tree in a temporary directory, never the live folders.
final class LaunchdFolderInventoryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BootCaptainModuleTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Restore permissions a test removed, so the tree can be deleted.
        if let paths = FileManager.default.enumerator(atPath: root.path) {
            for case let path as String in paths {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                       ofItemAtPath: root.appendingPathComponent(path).path)
            }
        }
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Fixture helpers

    private func path(_ relative: String) -> String {
        root.appendingPathComponent(relative).path
    }

    private func write(_ relative: String, plist: [String: Any]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try write(relative, data: data)
    }

    private func write(_ relative: String, data: Data) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private func inventory() -> LaunchdFolderInventory {
        LaunchdFolderInventory(
            folders: [
                .init(path: path("Library/LaunchDaemons"), mechanism: .launchDaemon),
                .init(path: path("Library/LaunchAgents"), mechanism: .launchAgent),
                .init(path: path("home/Library/LaunchAgents"), mechanism: .launchAgent),
            ],
            appFolders: [path("Applications"), path("home/Applications")])
    }

    // MARK: - Tests

    func testReadsFoldersWithTheScansIdentities() async throws {
        try write("Library/LaunchDaemons/com.vendor.daemon.plist",
                  plist: ["Label": "com.vendor.daemon", "Program": "/usr/local/bin/vendord"])
        try write("home/Library/LaunchAgents/com.vendor.agent.plist",
                  plist: ["Label": "com.vendor.agent", "ProgramArguments": ["/usr/local/bin/agent"],
                          "AssociatedBundleIdentifiers": ["com.vendor.app"]])
        try write("Library/LaunchAgents/notes.txt", data: Data("ignored".utf8))

        let snapshot = await inventory().observeInventory()

        XCTAssertEqual(snapshot.failures, [])
        XCTAssertEqual(Set(snapshot.items.map(\.id)), ["launchDaemon:com.vendor.daemon", "launchAgent:com.vendor.agent"])
        let agent = try XCTUnwrap(snapshot.items.first { $0.label == "com.vendor.agent" })
        XCTAssertEqual(agent.associatedBundleIdentifiers, ["com.vendor.app"])
        XCTAssertNil(agent.owningApp)
    }

    func testAbsentFoldersAreNormal() async {
        let snapshot = await inventory().observeInventory()
        XCTAssertTrue(snapshot.items.isEmpty)
        XCTAssertTrue(snapshot.failures.isEmpty)
    }

    func testUnparsablePlistIsListedUnderItsFileNameAsThePaneDoes() async throws {
        try write("Library/LaunchDaemons/broken.plist", data: Data("not a plist".utf8))
        let snapshot = await inventory().observeInventory()
        XCTAssertEqual(snapshot.items.map(\.id), ["launchDaemon:broken.plist"])
    }

    func testAppleLabelsAreLeftOut() async throws {
        try write("Library/LaunchDaemons/com.apple.thing.plist",
                  plist: ["Label": "com.apple.thing", "Program": "/usr/libexec/thing"])
        let snapshot = await inventory().observeInventory()
        XCTAssertTrue(snapshot.items.isEmpty)
    }

    func testEmbeddedPlistsAndProgramPathsAreAttributedToTheirApp() async throws {
        try write("Applications/Docker.app/Contents/Info.plist", plist: ["CFBundleIdentifier": "com.docker.docker"])
        try write("Applications/Docker.app/Contents/Library/LaunchDaemons/com.docker.vmnetd.plist",
                  plist: ["Label": "com.docker.vmnetd", "BundleProgram": "Contents/Library/LaunchServices/vmnetd"])
        try write("Library/LaunchDaemons/com.docker.socket.plist",
                  plist: ["Label": "com.docker.socket",
                          "ProgramArguments": [path("Applications/Docker.app/Contents/MacOS/socket")]])
        try write("home/Applications/Other.app/Contents/Info.plist", plist: ["CFBundleIdentifier": "org.other"])

        let snapshot = await inventory().observeInventory()

        let docker = AppIdentity(name: "Docker", bundleIdentifier: "com.docker.docker")
        let embedded = try XCTUnwrap(snapshot.items.first { $0.label == "com.docker.vmnetd" })
        XCTAssertEqual(embedded.id, "smAppServiceDaemon:com.docker.vmnetd")
        XCTAssertEqual(embedded.owningApp, docker)
        let socket = try XCTUnwrap(snapshot.items.first { $0.label == "com.docker.socket" })
        XCTAssertEqual(socket.owningApp, docker)
        XCTAssertEqual(snapshot.installedApps, ["com.docker.docker": "Docker", "org.other": "Other"])
    }

    func testUnreadableFolderIsAFailureNotAnEmptyFolder() async throws {
        try write("Library/LaunchDaemons/com.vendor.daemon.plist",
                  plist: ["Label": "com.vendor.daemon", "Program": "/usr/local/bin/vendord"])
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path("Library/LaunchDaemons"))
        if (try? FileManager.default.contentsOfDirectory(atPath: path("Library/LaunchDaemons"))) != nil {
            throw XCTSkip("Running with privileges that ignore folder permissions.")
        }

        let snapshot = await inventory().observeInventory()

        XCTAssertEqual(snapshot.failures.map(\.kind), [.unreadable])
        XCTAssertEqual(snapshot.failures.first?.path, path("Library/LaunchDaemons"))
        XCTAssertTrue(snapshot.items.isEmpty)
    }

    func testCancelledReadReportsCancellation() async throws {
        try write("Library/LaunchDaemons/com.vendor.daemon.plist",
                  plist: ["Label": "com.vendor.daemon", "Program": "/usr/local/bin/vendord"])
        let reader = inventory()
        let task = Task { () -> StartupInventorySnapshot in
            withUnsafeCurrentTask { $0?.cancel() }
            return await reader.observeInventory()
        }
        let snapshot = await task.value
        XCTAssertEqual(snapshot.failures.map(\.kind), [.cancelled])
    }
}
