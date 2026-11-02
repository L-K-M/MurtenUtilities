import Foundation

/// Credentials plus the instance origin they belong to. Asset URLs come from
/// the forge's API response, but they are still data from the network:
/// scoping the credentials to the origin the user typed keeps a redirected
/// or off-site asset URL from collecting them.
public struct DownloadAuth: Equatable, Sendable, CustomStringConvertible {
    public let credentials: ForgeCredentials
    public let origin: String

    public init(credentials: ForgeCredentials, origin: String) {
        self.credentials = credentials
        self.origin = origin
    }

    /// The header for a request to `url`: the credentials' own on the
    /// instance, nothing anywhere else.
    public func authorizationHeader(for url: String) -> String? {
        guard RepositoryURL.sameOrigin(url, origin) else { return nil }
        return credentials.authorizationHeader
    }

    public var description: String {
        "DownloadAuth(credentials: \(credentials), origin: \(origin))"
    }
}
