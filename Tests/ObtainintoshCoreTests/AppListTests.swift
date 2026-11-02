import XCTest
@testable import ObtainintoshCore

final class AppListTests: XCTestCase {
    private func app(_ name: String, _ sourceType: SourceType, _ url: String) -> TrackedApp {
        TrackedApp(id: "id-\(name)", name: name, sourceType: sourceType, sourceURL: url, currentVersion: "1.0",
                   latestVersion: "1.1", installPath: "/Applications/App.app", lastChecked: "2026-09-05T00:00:00Z",
                   downloaded: DownloadedRelease(version: "1.1", path: "/tmp/App.dmg"))
    }

    private func entry(_ name: String, _ url: String) -> ExportedApp {
        ExportedApp(name: name, sourceURL: url)
    }

    private func render(_ apps: [TrackedApp]) throws -> String {
        try AppList.render(apps, exportedAt: "2026-09-05T12:00:00Z", exportedBy: "MurtenUtilities/1.0")
    }

    private func object(_ json: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    func testExportWritesIdentityOnlyAndNeverTheApplicationKey() throws {
        var privateApp = app("Private", .forgejo, "https://git.example.internal/owner/private")
        privateApp.username = "alice"
        privateApp.accessToken = "secret-key"
        let publicApp = app("Public", .github, "https://github.com/owner/public")

        let json = try render([privateApp, publicApp])

        XCTAssertFalse(json.contains("secret-key"), json)
        XCTAssertFalse(json.contains("access_token"), json)
        let document = try object(json)
        XCTAssertEqual(document["format"] as? String, AppList.format)
        XCTAssertEqual(document["format_version"] as? Int, Int(AppList.formatVersionWithoutAssetFilters))
        XCTAssertEqual(document["exported_by"] as? String, "MurtenUtilities/1.0")
        let apps = try XCTUnwrap(document["apps"] as? [[String: String]])
        XCTAssertEqual(apps.count, 2)
        XCTAssertEqual(apps[0], ["name": "Private", "source_type": "forgejo",
                                 "source_url": "https://git.example.internal/owner/private", "username": "alice"])
        // Derived state stays out: nothing but the dialog's fields.
        XCTAssertEqual(apps[1], ["name": "Public", "source_type": "github",
                                 "source_url": "https://github.com/owner/public"])
        XCTAssertTrue(json.hasSuffix("\n"))
    }

    func testARenderedListParsesBackToTheSameEntries() throws {
        var privateApp = app("Private", .forgejo, "https://git.example.internal/owner/private")
        privateApp.username = "alice"
        privateApp.accessToken = "secret-key"
        let publicApp = app("Public", .github, "https://github.com/owner/public")

        let entries = try AppList.parse(try render([privateApp, publicApp]))

        XCTAssertEqual(entries, [
            ExportedApp(name: "Private", sourceType: .forgejo, sourceURL: "https://git.example.internal/owner/private",
                        username: "alice"),
            ExportedApp(name: "Public", sourceType: .github, sourceURL: "https://github.com/owner/public"),
        ])
    }

    func testParseRefusesWhatIsNotAProgramList() {
        XCTAssertThrowsError(try AppList.parse("{ not json")) { error in
            XCTAssertTrue("\(error)".hasPrefix("The file is not valid JSON:"), "\(error)")
        }

        // A raw apps.json, or any JSON without the marker, is turned away in words.
        for document in [#"{"apps": [], "settings": {}}"#,
                         #"{"format": "something-else", "format_version": 1, "apps": []}"#, "[]", "42"] {
            XCTAssertThrowsError(try AppList.parse(document)) { error in
                XCTAssertEqual("\(error)", "The file is not an Obtainintosh program list", document)
            }
        }

        // A missing version and a mistyped one are both version problems.
        for document in [#"{"format": "obtainintosh-app-list", "apps": []}"#,
                         #"{"format": "obtainintosh-app-list", "format_version": "1", "apps": []}"#,
                         #"{"format": "obtainintosh-app-list", "format_version": 1.5, "apps": []}"#] {
            XCTAssertThrowsError(try AppList.parse(document)) { error in
                XCTAssertEqual("\(error)", "The file does not say which program list format it uses", document)
            }
        }

        XCTAssertThrowsError(try AppList.parse(#"{"format": "obtainintosh-app-list", "format_version": 3, "apps": []}"#)) {
            XCTAssertTrue("\($0)".contains("newer version of Obtainintosh"), "\($0)")
            XCTAssertTrue("\($0)".contains("format 3"), "\($0)")
        }

        XCTAssertThrowsError(try AppList.parse(#"{"format": "obtainintosh-app-list", "format_version": 1}"#)) {
            XCTAssertTrue("\($0)".contains("missing field `apps`"), "\($0)")
        }
    }

    /// The standalone app reports serde's line and column; JSONDecoder has
    /// none, so the suite names the entry's position in the list instead.
    func testParseReportsAMalformedEntryByPosition() {
        let document = """
        {
          "format": "obtainintosh-app-list",
          "format_version": 1,
          "apps": [
            {"name": "A", "source_type": "gihub", "source_url": "https://github.com/o/a"}
          ]
        }
        """
        XCTAssertThrowsError(try AppList.parse(document)) { error in
            XCTAssertTrue("\(error)".contains("unknown variant `gihub`"), "\(error)")
            XCTAssertTrue("\(error)".contains("apps[0].source_type"), "\(error)")
        }
    }

    func testParseSkipsALeadingByteOrderMark() throws {
        let document = #"{"format": "obtainintosh-app-list", "format_version": 1, "apps": []}"#
        XCTAssertTrue(try AppList.parse("\u{feff}\(document)").isEmpty)
    }

    func testParseAcceptsMinimalHandWrittenEntriesAndASuppliedKey() throws {
        let document = """
        {
            "format": "obtainintosh-app-list",
            "format_version": 1,
            "apps": [
                {"name": "A", "source_url": "https://github.com/o/a"},
                {"name": "B", "source_type": "forgejo", "source_url": "https://git.example.internal/o/b",
                 "username": "bob", "access_token": "key-b", "unknown_field": true}
            ]
        }
        """
        let entries = try AppList.parse(document)
        XCTAssertEqual(entries.count, 2)
        XCTAssertNil(entries[0].sourceType)
        XCTAssertEqual(entries[1].accessToken, "key-b")
    }

    func testPlanImportAppliesTheAddDialogRules() {
        var forgejoWithKey = entry("Private", "https://git.example.internal/o/private")
        forgejoWithKey.sourceType = .forgejo
        forgejoWithKey.username = "alice"
        forgejoWithKey.accessToken = "key"
        var githubWithStrayKey = entry("Public", "https://github.com/o/public")
        githubWithStrayKey.username = "alice"
        githubWithStrayKey.accessToken = "key"
        var forgejoWithPaddedCredentials = entry("Padded key", "https://codeberg.org/o/padded-key")
        forgejoWithPaddedCredentials.username = "  bob  "
        forgejoWithPaddedCredentials.accessToken = "   "

        let plan = AppList.planImport([
            entry("  Padded  ", "  https://github.com/o/padded  "),
            entry("", "https://github.com/o/nameless"),
            entry("No URL", "   "),
            entry("Unknown host", "https://git.example.internal/o/unknown"),
            entry("Codeberg", "https://codeberg.org/o/detected"),
            forgejoWithKey,
            githubWithStrayKey,
            forgejoWithPaddedCredentials,
        ])

        XCTAssertEqual(plan.apps.map(\.name), ["Padded", "Codeberg", "Private", "Public", "Padded key"])
        XCTAssertTrue(plan.apps.allSatisfy { $0.id.isEmpty })

        // Credentials are cleaned the way the dialog's are.
        XCTAssertEqual(plan.apps[4].username, "bob")
        XCTAssertNil(plan.apps[4].accessToken)

        XCTAssertEqual(plan.apps[0].sourceURL, "https://github.com/o/padded")
        XCTAssertEqual(plan.apps[0].sourceType, .github)
        XCTAssertEqual(plan.apps[1].sourceType, .forgejo)

        XCTAssertEqual(plan.apps[2].username, "alice")
        XCTAssertEqual(plan.apps[2].accessToken, "key")
        // Credentials against a forge that never sends them are dropped.
        XCTAssertNil(plan.apps[3].username)
        XCTAssertNil(plan.apps[3].accessToken)

        XCTAssertEqual(plan.rejected, [
            AppList.RejectedEntry(label: "entry 2", reason: "The program name is empty"),
            AppList.RejectedEntry(label: "No URL", reason: "The repository URL is empty"),
            AppList.RejectedEntry(label: "Unknown host",
                                  reason: "Unsupported source URL. Add \"source_type\": \"forgejo\" to the entry if "
                                    + "https://git.example.internal/o/unknown is a Forgejo instance."),
        ])
    }

    func testRejectedEntriesQuoteTheFileBackWithinBounds() {
        let longName = "Name " + String(repeating: "x", count: 500)
        let longURL = "https://git.example.internal/" + String(repeating: "o", count: 500) + "/repo"

        let plan = AppList.planImport([entry(longName, "   "), entry("Unknown  host\n\twith   spaces", longURL)])

        XCTAssertEqual(plan.rejected.count, 2)
        let nameLabel = plan.rejected[0].label
        XCTAssertEqual(nameLabel.count, 60, nameLabel)
        XCTAssertTrue(nameLabel.hasPrefix("Name xxx"), nameLabel)
        XCTAssertTrue(nameLabel.hasSuffix("…"), nameLabel)

        // Whitespace is collapsed so a multi-line name stays one line.
        XCTAssertEqual(plan.rejected[1].label, "Unknown host with spaces")
        let reason = plan.rejected[1].reason
        XCTAssertLessThan(reason.count, 200, reason)
        XCTAssertTrue(reason.contains("https://git.example.internal/ooo"), reason)
        XCTAssertTrue(reason.contains("… is a Forgejo instance."), reason)
    }

    func testAPrivateForgejoEntryIsFlaggedAsMissingItsKeyAfterARoundTrip() throws {
        var privateApp = app("Private", .forgejo, "https://git.example.internal/o/private")
        privateApp.username = "alice"
        privateApp.accessToken = "key"
        XCTAssertFalse(AppList.isMissingApplicationKey(privateApp))

        let plan = AppList.planImport(try AppList.parse(try render([privateApp])))

        XCTAssertEqual(plan.apps.count, 1)
        XCTAssertTrue(AppList.isMissingApplicationKey(plan.apps[0]))

        // A public Forgejo repository has no username, so nothing is missing.
        XCTAssertFalse(AppList.isMissingApplicationKey(app("Public", .forgejo, "https://codeberg.org/o/public")))
    }

    func testSuggestedNameIsDatedAndCarriesTheExtension() throws {
        let components = DateComponents(year: 2026, month: 9, day: 5, hour: 12)
        var calendar = Calendar(identifier: .gregorian)
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        calendar.timeZone = utc
        let date = try XCTUnwrap(calendar.date(from: components))
        XCTAssertEqual(AppList.suggestedFileName(for: date, timeZone: utc), "Obtainintosh Programs 2026-09-05.obtainintosh")
    }

    func testDefaultExtensionIsAddedOnlyWhenThereIsNone() {
        func path(_ text: String) -> String { AppList.withDefaultExtension(URL(fileURLWithPath: text)).path }
        XCTAssertEqual(path("/tmp/list"), "/tmp/list.obtainintosh")
        XCTAssertEqual(path("/tmp/list.obtainintosh"), "/tmp/list.obtainintosh")
        XCTAssertEqual(path("/tmp/list.json"), "/tmp/list.json")
        // A trailing dot is no extension, and is not kept either.
        XCTAssertEqual(path("/tmp/list."), "/tmp/list.obtainintosh")
        XCTAssertEqual(path("/tmp/list..."), "/tmp/list.obtainintosh")
        XCTAssertEqual(path("/"), "/")
    }

    func testAFilteredEntryRoundTripsUnderTheNewerFormatVersion() throws {
        var seance = app("Seance", .github, "https://github.com/L-K-M/Hauntware")
        seance.assetFilter = "seance"
        let planchette = app("Planchette", .github, "https://github.com/L-K-M/Hauntware")

        let json = try render([seance, planchette])

        // An older reader would track the wrong program for this file, so it must refuse it.
        let document = try object(json)
        XCTAssertEqual(document["format_version"] as? Int, Int(AppList.formatVersion))
        let entries = try AppList.parse(json)
        XCTAssertEqual(entries[0].assetFilter, "seance")
        XCTAssertNil(entries[1].assetFilter)
        let apps = try XCTUnwrap(document["apps"] as? [[String: Any]])
        XCTAssertNil(apps[1]["asset_filter"], json)
    }

    func testPlanImportStoresAssetFiltersCanonicallyAndRejectsUnusableOnes() {
        let hauntware = "https://github.com/L-K-M/Hauntware"
        var sync = entry("Seance Sync", hauntware)
        sync.assetFilter = "  Seance Sync "
        var pasted = entry("Seance", hauntware)
        pasted.assetFilter = "seance-macos-universal.zip"
        var blank = entry("Hauntware", hauntware)
        blank.assetFilter = "   "
        var everything = entry("Everything", hauntware)
        everything.assetFilter = "*"

        let plan = AppList.planImport([sync, pasted, blank, everything])

        XCTAssertEqual(plan.apps.map(\.assetFilter), ["seance-sync", "seance", nil])
        XCTAssertEqual(plan.rejected.count, 1)
        XCTAssertEqual(plan.rejected[0].label, "Everything")
        XCTAssertTrue(plan.rejected[0].reason.contains("matches every file"), plan.rejected[0].reason)
    }

    func testDisplayNameIsTheFinalComponent() {
        XCTAssertEqual(AppList.displayName(URL(fileURLWithPath: "/tmp/Obtainintosh Programs.obtainintosh")),
                       "Obtainintosh Programs.obtainintosh")
        XCTAssertEqual(AppList.displayName(URL(fileURLWithPath: "/")), "/")
    }

    func testTheBundleIdentifierTravelsWithTheEntry() throws {
        var tracked = app("Tool", .github, "https://github.com/owner/tool")
        tracked.bundleID = "com.example.tool"
        let plan = AppList.planImport(try AppList.parse(try render([tracked])))
        XCTAssertEqual(plan.apps.first?.bundleID, "com.example.tool")
    }
}
