import Foundation
import ObtainintoshCore

/// The live observer: the store's file, the application and font folders,
/// and the forges, with tokens from the vault's memory only.
public struct LiveUpdateObserver: UpdateObserving {
    private let listURL: URL
    private let detector: InstalledVersionDetecting
    private let lookup: ReleaseLooking
    private let vault: CredentialVault

    public init(listURL: URL, detector: InstalledVersionDetecting, lookup: ReleaseLooking, vault: CredentialVault) {
        self.listURL = listURL
        self.detector = detector
        self.lookup = lookup
        self.vault = vault
    }

    public func trackedList() throws -> TrackedAppData? {
        try TrackedListStore.readSnapshot(at: listURL)
    }

    /// A font is read where the pane last found it; a program is found by
    /// bundle identifier or name.
    public func installedVersions(of apps: [TrackedApp]) async -> [InstalledVersion?] {
        let fontLookups: [FontLookup?] = apps.map { app in
            guard let path = app.installPath, FontFile.isFontFile(path) else { return nil }
            return .lastFoundAt(path)
        }
        let fonts = await detector.detectFonts(fontLookups)
        let programs = await detector.detectPrograms(apps)
        return zip(fonts, programs).map { font, program in
            switch font {
            case .notAFont: return program
            case .installed(let installed): return installed
            case .notInstalled: return nil
            }
        }
    }

    public func gitHubAllowance() async -> Int {
        await vault.cachedToken(.gitHub) == nil
            ? GitHubRateBudget.unauthenticatedAllowance : GitHubRateBudget.authenticatedAllowance
    }

    public func latestRelease(of app: TrackedApp, budget: RequestBudget) async throws -> Release {
        var credentials = LookupCredentials(gitHubToken: await vault.cachedToken(.gitHub))
        if app.sourceType == .forgejo && app.hasStoredAccessToken {
            guard let key = await vault.cachedToken(.forgejo(appID: app.id)) else {
                throw LookupFailure(.permissionDenied, "Its application key is read from the Keychain only when you "
                    + "check from Obtainintosh, so it was not checked in the background.")
            }
            credentials.forge = ForgeCredentials(username: app.username, token: key)
        }
        return try await lookup.latestRelease(of: app, credentials: credentials, budget: budget)
    }
}
