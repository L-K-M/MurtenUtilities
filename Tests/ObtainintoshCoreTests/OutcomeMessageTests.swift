import XCTest
@testable import ObtainintoshCore

/// The wording of the standalone app's notifications (appStore.ts).
final class OutcomeMessageTests: XCTestCase {
    private func outcome(_ name: String, _ state: CheckOutcome.State, _ message: String? = nil) -> CheckOutcome {
        CheckOutcome(appID: name, appName: name, state: state, message: message)
    }

    func testCheckFailureSummaries() {
        XCTAssertNil(CheckOutcome.failureSummary([outcome("A", .succeeded)]))
        XCTAssertEqual(CheckOutcome.failureSummary([outcome("A", .succeeded), outcome("B", .failed, "offline")]),
                       "B: offline")
        XCTAssertEqual(CheckOutcome.failureSummary([outcome("B", .skipped)]), "B: The update check did not complete")
        XCTAssertEqual(CheckOutcome.failureSummary([outcome("A", .failed), outcome("B", .unsupported)]),
                       "Update checks failed or were skipped for all 2 apps")
        XCTAssertEqual(CheckOutcome.failureSummary([outcome("A", .failed), outcome("B", .skipped),
                                                    outcome("C", .succeeded)]),
                       "2 of 3 update checks failed or were skipped")
    }

    func testOutcomesOfAppliedAndDiscardedResults() {
        let app = TrackedApp(id: "id", name: "Tool", sourceType: .github, sourceURL: "u")
        let update = CheckOwnedUpdate(currentVersion: nil, installPath: nil, latestVersion: nil,
                                      attempt: .unsuccessful(at: "t", state: .failed, message: "offline"))
        XCTAssertEqual(CheckOutcome.make(for: app, update: update, application: .applied).state, .failed)
        XCTAssertEqual(CheckOutcome.make(for: app, update: update, application: .appRemoved).message,
                       "The program was removed while its update check was running")
        XCTAssertEqual(CheckOutcome.make(for: app, update: update, application: .dependenciesChanged).state, .skipped)
    }

    func testImportSummaries() {
        XCTAssertEqual(ImportSummary(fileName: "list.obtainintosh", added: 0, duplicates: 3).message,
                       "No programs were imported from list.obtainintosh (3 were already tracked)")
        XCTAssertEqual(ImportSummary(fileName: "list.obtainintosh", added: 1, duplicates: 1).message,
                       "Imported 1 program from list.obtainintosh (1 was already tracked)")
        XCTAssertEqual(ImportSummary(fileName: "f", added: 2, duplicates: 0).message, "Imported 2 programs from f")

        XCTAssertEqual(ImportSummary(fileName: "f", added: 1, duplicates: 0, missingKeys: 1).missingKeysMessage,
                       "1 imported Forgejo program needs its application key — keys are never written to an export. "
                        + "Edit the program to add it.")
        XCTAssertNil(ImportSummary(fileName: "f", added: 1, duplicates: 0).missingKeysMessage)

        let rejected = (1...5).map { AppList.RejectedEntry(label: "E\($0)", reason: "bad") }
        XCTAssertEqual(ImportSummary(fileName: "f", added: 0, duplicates: 0, rejected: rejected).rejectedMessage,
                       "5 entries of f could not be imported — E1: bad; E2: bad; E3: bad; and 2 more entries")
    }
}
