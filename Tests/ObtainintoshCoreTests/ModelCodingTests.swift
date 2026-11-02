import XCTest
@testable import ObtainintoshCore

final class ModelCodingTests: XCTestCase {
    private func decode(_ json: String) throws -> TrackedAppData {
        try JSONDecoder().decode(TrackedAppData.self, from: Data(json.utf8))
    }

    func testLoadsOlderDataWithMissingNonIdentityFields() throws {
        let data = try decode("""
        {
            "apps": [{"id": "legacy-id", "name": "Legacy App", "source_type": "github",
                      "source_url": "https://github.com/owner/legacy"}],
            "settings": {"github_token": "legacy-token"}
        }
        """)

        let legacy = try XCTUnwrap(data.apps.first)
        XCTAssertEqual(legacy.name, "Legacy App")
        XCTAssertEqual(legacy.sourceURL, "https://github.com/owner/legacy")
        XCTAssertNil(legacy.currentVersion)
        XCTAssertNil(legacy.latestVersion)
        XCTAssertNil(legacy.installPath)
        XCTAssertNil(legacy.lastChecked)
        XCTAssertNil(legacy.accessToken)
        XCTAssertFalse(legacy.hasStoredAccessToken)
        XCTAssertEqual(data.settings.githubToken, "legacy-token")
        XCTAssertNil(data.settings.gitlabToken)
    }

    func testLoadsADataFileWrittenBeforeForgejoSupport() throws {
        let data = try decode("""
        {
            "apps": [{"id": "abc", "name": "Obtainintosh", "source_type": "github",
                      "source_url": "https://github.com/L-K-M/Obtainintosh", "current_version": "1.2.1",
                      "latest_version": null, "install_path": null, "last_checked": null}],
            "settings": {"github_token": null, "gitlab_token": null},
            "self_entry_seeded": true
        }
        """)
        XCTAssertEqual(data.apps.count, 1)
        XCTAssertNil(data.apps[0].username)
        XCTAssertNil(data.apps[0].accessToken)
        XCTAssertTrue(data.selfEntrySeeded)
    }

    func testARecordWithoutItsIdentityIsRefused() {
        XCTAssertThrowsError(try decode(#"{"apps": [{"id": "x", "name": "No source"}]}"#))
    }

    func testAppDescriptionsRedactTheApplicationKey() {
        let app = TrackedApp(id: "id", name: "Private", sourceType: .forgejo, sourceURL: "https://codeberg.org/o/r",
                             username: "alice", accessToken: "key123")
        var dumped = ""
        dump(app, to: &dumped)
        for rendered in ["\(app)", String(reflecting: app), dumped] {
            XCTAssertFalse(rendered.contains("key123"), "leaked the key: \(rendered)")
            XCTAssertTrue(rendered.contains(redactedSecret), rendered)
            XCTAssertTrue(rendered.contains("alice"), rendered)
        }
    }

    func testTheSuiteWritesNoSecrets() throws {
        let data = TrackedAppData(
            apps: [TrackedApp(id: "id", name: "Private", sourceType: .forgejo, sourceURL: "https://codeberg.org/o/r",
                              username: "alice", accessToken: "key123", bundleID: "org.example.private",
                              hasStoredAccessToken: true)],
            settings: StoredSettings(githubToken: "ghp_secret"), selfEntrySeeded: true, removedAppIDs: ["gone"])

        let json = String(decoding: try JSONEncoder().encode(data.withoutSecrets), as: UTF8.self)

        XCTAssertFalse(json.contains("key123"), json)
        XCTAssertFalse(json.contains("ghp_secret"), json)
        let decoded = try decode(json)
        XCTAssertTrue(decoded.apps[0].hasStoredAccessToken)
        XCTAssertEqual(decoded.apps[0].bundleID, "org.example.private")
        XCTAssertEqual(decoded.removedAppIDs, ["gone"])
        XCTAssertTrue(decoded.selfEntrySeeded)
    }

    func testCheckMessagesAreBounded() {
        XCTAssertEqual(boundedCheckMessage("  two\n\tlines  "), "two lines")
        let long = String(repeating: "word ", count: 100)
        let bounded = boundedCheckMessage(long)
        XCTAssertEqual(bounded.count, 240)
        XCTAssertTrue(bounded.hasSuffix("..."))
    }
}
