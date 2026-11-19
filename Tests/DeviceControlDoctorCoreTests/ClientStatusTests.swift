import XCTest
@testable import DoctorCore

final class ClientStatusTests: XCTestCase {
    private let home = "/Users/u"

    // MARK: - Presence

    func testPresenceOfAnInstalledCopy() {
        let presence = ClientStatus.presence(of: ["/Applications/Foo.app"], home: home, exists: { _ in true })

        XCTAssertEqual(presence, .installed(path: "/Applications/Foo.app"))
    }

    func testPresencePrefersAnInstalledCopyOverTheTrash() {
        let presence = ClientStatus.presence(of: ["/Users/u/.Trash/Foo.app", "/Applications/Foo.app"],
                                             home: home, exists: { _ in true })

        XCTAssertEqual(presence, .installed(path: "/Applications/Foo.app"))
    }

    func testPresenceOfOnlyATrashedCopy() {
        let presence = ClientStatus.presence(of: ["/Users/u/.Trash/Foo.app"], home: home, exists: { _ in true })

        XCTAssertEqual(presence, .inTrash(path: "/Users/u/.Trash/Foo.app"))
    }

    func testPresenceOfACopyOnAnUnmountedVolume() {
        let presence = ClientStatus.presence(of: ["/Volumes/Ext/Apps/Foo.app"], home: home, exists: { _ in false })

        XCTAssertEqual(presence, .offline(path: "/Volumes/Ext/Apps/Foo.app"))
    }

    func testPresenceIsMissingWhenTheVolumeIsMountedOrThereAreNoPaths() {
        let mounted = ClientStatus.presence(of: ["/Volumes/Ext/Apps/Foo.app"], home: home,
                                            exists: { $0 == "/Volumes/Ext" })
        XCTAssertEqual(mounted, .missing)
        XCTAssertEqual(ClientStatus.presence(of: [], home: home, exists: { _ in true }), .missing)
    }

    // MARK: - Trash

    func testIsInTrash() {
        XCTAssertTrue(ClientStatus.isInTrash("/Volumes/Ext/.Trashes/501/Foo.app", home: home))
        XCTAssertTrue(ClientStatus.isInTrash("/Users/u/.Trash/Foo.app", home: "/Users/u/"))
        XCTAssertFalse(ClientStatus.isInTrash("/Users/u/Trash/Foo.app", home: home))
    }

    // MARK: - Volumes

    func testVolumeRoot() {
        XCTAssertEqual(ClientStatus.volumeRoot(of: "/Volumes/Ext/x"), "/Volumes/Ext")
        XCTAssertNil(ClientStatus.volumeRoot(of: "/Volumes/Ext"))
        XCTAssertNil(ClientStatus.volumeRoot(of: "/Applications/x"))
    }

    // MARK: - System clients

    func testIsSystem() {
        XCTAssertTrue(ClientStatus.isSystem(client: "/usr/libexec/sshd-keygen-wrapper", kind: .path,
                                            presence: .installed(path: "/usr/libexec/sshd-keygen-wrapper")))
        XCTAssertFalse(ClientStatus.isSystem(client: "/usr/local/bin/node", kind: .path,
                                             presence: .installed(path: "/usr/local/bin/node")))
        XCTAssertTrue(ClientStatus.isSystem(client: "com.apple.Terminal", kind: .bundleIdentifier,
                                            presence: .installed(path: "/System/Applications/Utilities/Terminal.app")))
        XCTAssertFalse(ClientStatus.isSystem(client: "com.apple.dt.Xcode", kind: .bundleIdentifier,
                                             presence: .installed(path: "/Applications/Xcode.app")))
        XCTAssertTrue(ClientStatus.isSystem(client: "com.apple.screensharing.agent", kind: .bundleIdentifier,
                                            presence: .missing))
        XCTAssertFalse(ClientStatus.isSystem(client: "com.example.app", kind: .bundleIdentifier,
                                             presence: .missing))
        XCTAssertFalse(ClientStatus.isSystem(client: "com.apple.Foo", kind: .bundleIdentifier,
                                             presence: .inTrash(path: "/Users/u/.Trash/Foo.app")))
    }

    // MARK: - Enclosing app

    func testEnclosingAppPath() {
        XCTAssertEqual(ClientStatus.enclosingAppPath(of: "/Applications/Foo.app/Contents/MacOS/foo"),
                       "/Applications/Foo.app")
        XCTAssertEqual(ClientStatus.enclosingAppPath(of: "/A/Outer.app/Contents/MacOS/Inner.app/Contents/MacOS/inner"),
                       "/A/Outer.app/Contents/MacOS/Inner.app")
        XCTAssertNil(ClientStatus.enclosingAppPath(of: "/usr/local/bin/node"))
        XCTAssertEqual(ClientStatus.enclosingAppPath(of: "/Applications/Foo.app"), "/Applications/Foo.app")
    }
}
