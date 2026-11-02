import XCTest
@testable import ObtainintoshCore

final class ForgeCredentialsTests: XCTestCase {
    func testCredentialsDropBlankEntries() {
        let blank = ForgeCredentials(username: "   ", token: "")
        XCTAssertEqual(blank, ForgeCredentials())
        XCTAssertNil(blank.username)
        XCTAssertNil(blank.token)

        let trimmed = ForgeCredentials(username: " alice ", token: " key ")
        XCTAssertEqual(trimmed.username, "alice")
        XCTAssertEqual(trimmed.token, "key")
    }

    func testDescriptionsRedactTheApplicationKey() {
        let credentials = ForgeCredentials(username: "alice", token: "key123")
        let auth = DownloadAuth(credentials: credentials, origin: "https://git.example.internal")

        var dumped = ""
        dump(credentials, to: &dumped)
        for rendered in ["\(credentials)", String(reflecting: credentials), "\(auth)", dumped] {
            XCTAssertFalse(rendered.contains("key123"), "leaked the key: \(rendered)")
            XCTAssertTrue(rendered.contains(redactedSecret), rendered)
            // The username is not a secret and stays readable.
            XCTAssertTrue(rendered.contains("alice"), rendered)
        }
    }

    func testUsernameAndKeyAuthenticateWithBasic() {
        // Forgejo reads a key out of the Basic password, and Basic also works
        // on the web routes that serve release assets.
        let credentials = ForgeCredentials(username: "alice", token: "key123")
        XCTAssertEqual(credentials.authorizationHeader, "Basic YWxpY2U6a2V5MTIz")
    }

    func testKeyWithoutUsernameUsesTheTokenScheme() {
        XCTAssertEqual(ForgeCredentials(token: "key123").authorizationHeader, "token key123")
    }

    func testNoKeySendsNoAuthorization() {
        XCTAssertNil(ForgeCredentials().authorizationHeader)
        // A username on its own authenticates nothing.
        XCTAssertNil(ForgeCredentials(username: "alice").authorizationHeader)
    }

    func testDownloadAuthIsScopedToTheInstance() {
        let auth = DownloadAuth(credentials: ForgeCredentials(username: "alice", token: "key123"),
                                origin: try! RepositoryURL.parseForgejo("https://git.example.internal/owner/repo").baseURL)

        // Assets served by the instance itself get the credentials…
        XCTAssertNotNil(auth.authorizationHeader(
            for: "https://git.example.internal/owner/repo/releases/download/v1/App.dmg"))
        // …anywhere else does not, however the asset URL got there.
        XCTAssertNil(auth.authorizationHeader(for: "https://cdn.example.com/App.dmg"))
        XCTAssertNil(auth.authorizationHeader(
            for: "http://git.example.internal/owner/repo/releases/download/v1/App.dmg"))
    }

    func testCredentialsAreKeptOnlyForTheForgeThatUsesThem() {
        let forgejo = ForgeCredentials.forSource(.forgejo, username: "alice", token: "key123")
        XCTAssertEqual(forgejo.username, "alice")
        XCTAssertEqual(forgejo.token, "key123")

        // Retyping a program to a forge that authenticates differently drops the key.
        for sourceType in [SourceType.github, .gitlab] {
            XCTAssertEqual(ForgeCredentials.forSource(sourceType, username: "alice", token: "key123"),
                           ForgeCredentials(), "\(sourceType)")
        }
    }

    func testSourceTypeFallsBackToDetectionOnlyWhenUnset() throws {
        // An explicit pick wins, so a private instance on an unremarkable host is reachable.
        XCTAssertEqual(try SourceInput(url: "https://git.example.internal/o/r", name: "R", sourceType: .forgejo)
            .resolvedSourceType(), .forgejo)
        XCTAssertEqual(try SourceInput(url: "https://github.com/owner/repo", name: "R").resolvedSourceType(), .github)
        XCTAssertThrowsError(try SourceInput(url: "https://git.example.internal/o/r", name: "R").resolvedSourceType())
    }

    func testForgejoErrorsExplainCredentialFailures() {
        for status in [401, 403] {
            XCTAssertTrue(ForgeMessages.forgejoError(status: status).contains("application key"))
        }
        XCTAssertTrue(ForgeMessages.forgejoError(status: 500).contains("Forgejo API error"))
    }
}
