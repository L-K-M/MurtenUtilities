import XCTest
@testable import ObtainintoshCore

/// The Add Program dialog's behaviour (AddAppDialog.test.ts and
/// programNames.test.ts in the standalone app), on the form's state.
final class ProgramFormTests: XCTestCase {
    private let hauntware = "https://github.com/L-K-M/Hauntware"
    private let hauntwarePrograms = ReleasePrograms(version: "1.9.0",
                                                    programs: ["planchette", "poltergeist", "seance", "seance-sync"],
                                                    defaultProgram: "planchette")

    private func enterURL(_ url: String, into form: inout ProgramForm) -> ProgramForm.LookupChange {
        form.url = url
        form.urlDidChange()
        return form.lookupChange()
    }

    func testOffersTheProgramsOfAMultiProgramReleaseAndNamesTheEntryAfterTheChoice() {
        var form = ProgramForm()
        guard case .lookup(let key, let input) = enterURL(hauntware, into: &form) else {
            return XCTFail("expected a lookup")
        }
        XCTAssertEqual(input.url, hauntware)
        XCTAssertNil(input.sourceType)
        XCTAssertEqual(form.name, "Hauntware")

        form.receive(hauntwarePrograms, forKey: key)

        XCTAssertEqual(form.offeredPrograms, hauntwarePrograms.programs)
        XCTAssertEqual(form.defaultProgramHint, "Without a choice, Obtainintosh downloads planchette.")

        form.chooseProgram("seance-sync")
        XCTAssertEqual(form.assetFilter, "seance-sync")
        XCTAssertEqual(form.name, "Seance Sync")
        XCTAssertEqual(form.chosenProgram, "seance-sync")
        XCTAssertNil(form.defaultProgramHint)

        XCTAssertEqual(form.input, SourceInput(url: hauntware, name: "Seance Sync", assetFilter: "seance-sync"))
    }

    func testKeepsATypedProgramWhenTheLookupFails() {
        var form = ProgramForm()
        _ = enterURL(hauntware, into: &form)
        // No reply arrives: the lookup failed.
        form.assetFilter = " Seance "

        XCTAssertTrue(form.offeredPrograms.isEmpty)
        XCTAssertEqual(form.input.name, "Hauntware")
        XCTAssertEqual(form.input.assetFilter, "Seance")
    }

    func testOffersNoChoiceForAReleaseWithASingleProgram() {
        var form = ProgramForm()
        guard case .lookup(let key, _) = enterURL("https://github.com/owner/tool", into: &form) else {
            return XCTFail("expected a lookup")
        }
        form.receive(ReleasePrograms(version: "2.0.0", programs: ["tool"], defaultProgram: "tool"), forKey: key)

        XCTAssertTrue(form.offeredPrograms.isEmpty)
        XCTAssertEqual(form.name, "tool")
    }

    func testDropsTheReplyOfALookupWhoseURLHasSinceChanged() {
        var form = ProgramForm()
        guard case .lookup(let staleKey, _) = enterURL(hauntware, into: &form) else {
            return XCTFail("expected a lookup")
        }
        guard case .lookup = enterURL("https://github.com/owner/tool", into: &form) else {
            return XCTFail("expected a new lookup")
        }

        form.receive(hauntwarePrograms, forKey: staleKey)

        XCTAssertTrue(form.offeredPrograms.isEmpty)
    }

    func testUnchangedInputsDoNotLookUpAgainAndPartialURLsCancel() {
        var form = ProgramForm()
        guard case .lookup = enterURL(hauntware, into: &form) else { return XCTFail("expected a lookup") }
        XCTAssertEqual(form.lookupChange(), .unchanged)
        XCTAssertEqual(enterURL("https://github.com/L-K-M", into: &form), .cancel)
    }

    func testANameTheUserTypedIsKept() {
        var form = ProgramForm()
        form.name = "My Name"
        _ = enterURL(hauntware, into: &form)
        XCTAssertEqual(form.name, "My Name")

        form.chooseProgram("seance")
        XCTAssertEqual(form.name, "My Name")
    }

    func testEditingNeverRenamesAndKeepsGitLabSelectable() {
        let app = TrackedApp(id: "id", name: "Old", sourceType: .gitlab, sourceURL: "https://gitlab.com/o/old")
        var form = ProgramForm(editing: app, accessToken: nil)
        _ = enterURL("https://gitlab.com/o/new", into: &form)
        form.chooseProgram("seance")

        XCTAssertEqual(form.name, "Old")
        XCTAssertTrue(form.sourceOptions.contains(.source(.gitlab)))
        XCTAssertFalse(ProgramForm().sourceOptions.contains(.source(.gitlab)))
    }

    func testCredentialsAreSubmittedForForgejoOnly() {
        var form = ProgramForm()
        form.url = "https://git.example.internal/o/r"
        form.name = "R"
        form.username = " alice "
        form.accessToken = " key "
        XCTAssertNil(form.input.username)

        form.sourceChoice = .source(.forgejo)
        XCTAssertEqual(form.input.username, "alice")
        XCTAssertEqual(form.input.accessToken, "key")
        XCTAssertEqual(form.input.sourceType, .forgejo)
    }

    func testValidation() {
        var form = ProgramForm()
        XCTAssertEqual(form.validationError, "Please enter a repository URL")
        form.url = "https://github.com/o/r"
        form.name = "  "
        XCTAssertEqual(form.validationError, "Please enter a program name")
        form.name = "R"
        XCTAssertNil(form.validationError)
    }

    func testRepositoryNamesComeFromAnyHost() {
        XCTAssertEqual(ProgramForm.repositoryName(in: "https://github.com/owner/repo.git"), "repo")
        XCTAssertEqual(ProgramForm.repositoryName(in: "git.example.internal/owner/repo/releases"), "repo")
        XCTAssertNil(ProgramForm.repositoryName(in: "https://github.com/owner"))
    }

    func testProgramDisplayNames() {
        XCTAssertEqual(ProgramForm.displayName(forProgram: "seance"), "Seance")
        XCTAssertEqual(ProgramForm.displayName(forProgram: "seance-sync"), "Seance Sync")
        XCTAssertEqual(ProgramForm.displayName(forProgram: "mac-mouse-fix"), "Mac Mouse Fix")
        XCTAssertEqual(ProgramForm.displayName(forProgram: "7zip"), "7zip")
        XCTAssertEqual(ProgramForm.displayName(forProgram: "séance"), "Séance")
    }

    // MARK: - Applying the dialog

    func testAnEditOfTheSourceResetsWhatBelongedToTheOldOne() throws {
        let app = TrackedApp(id: "id", name: "Tool", sourceType: .github, sourceURL: "https://github.com/o/tool",
                             latestVersion: "2.0", lastChecked: "t",
                             lastCheckAttempt: .succeeded(at: "t"),
                             downloaded: DownloadedRelease(version: "2.0", path: "/tmp/x"))

        let renamed = try SourceInput(url: "https://github.com/o/tool", name: "Renamed", sourceType: .github)
            .applied(to: app)
        XCTAssertEqual(renamed.latestVersion, "2.0")
        XCTAssertEqual(renamed.name, "Renamed")

        let moved = try SourceInput(url: "https://github.com/o/other", name: "Tool").applied(to: app)
        XCTAssertNil(moved.latestVersion)
        XCTAssertNil(moved.lastChecked)
        XCTAssertNil(moved.lastCheckAttempt)
        XCTAssertNil(moved.downloaded)
        XCTAssertEqual(moved.sourceURL, "https://github.com/o/other")
    }

    func testRetypingAProgramDropsCredentialsTheNewForgeNeverSends() throws {
        let app = TrackedApp(id: "id", name: "Tool", sourceType: .forgejo, sourceURL: "https://codeberg.org/o/tool",
                             username: "alice")
        let updated = try SourceInput(url: "https://codeberg.org/o/tool", name: "Tool", sourceType: .github,
                                      username: "alice", accessToken: "key").applied(to: app)
        XCTAssertNil(updated.username)
        XCTAssertNil(updated.accessToken)
    }

    func testANewProgramIsCanonical() throws {
        let app = try SourceInput(url: hauntware, name: "Seance", assetFilter: "Seance", bundleID: " com.x.seance ")
            .makeApp()
        XCTAssertEqual(app.sourceType, .github)
        XCTAssertEqual(app.assetFilter, "seance")
        XCTAssertEqual(app.bundleID, "com.x.seance")
        XCTAssertTrue(app.id.isEmpty)
    }
}
