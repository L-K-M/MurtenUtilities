import Foundation
import ObtainintoshCore

/// The credentials a lookup may send: the GitHub token for GitHub, the
/// program's own Forgejo credentials for Forgejo.
public struct LookupCredentials: Sendable {
    public var gitHubToken: String?
    public var forge: ForgeCredentials

    public init(gitHubToken: String? = nil, forge: ForgeCredentials = ForgeCredentials()) {
        self.gitHubToken = gitHubToken
        self.forge = forge
    }
}
