import Foundation
import ObtainintoshCore
import ObtainintoshServices

/// Everything the module reaches outside itself, so tests can substitute
/// fixtures for the file system, the forges and the Keychain.
struct ObtainintoshEnvironment {
    /// The suite's tracked list.
    var listURL: URL
    /// The standalone app's list, offered for a one-time import.
    var standaloneListURL: URL
    var lookup: ReleaseLooking
    var detector: InstalledVersionDetecting
    var downloader: ReleaseDownloader
    var vault: CredentialVault
    var revealer: FileRevealing
    var now: @Sendable () -> Date

    /// What the background check reads: the same list, folders and forges,
    /// with tokens only from the vault's memory.
    var observer: UpdateObserving {
        LiveUpdateObserver(listURL: listURL, detector: detector, lookup: lookup, vault: vault)
    }

    static func live() -> ObtainintoshEnvironment {
        let transport = URLSessionTransport.shared
        return ObtainintoshEnvironment(
            listURL: TrackedListStore.defaultURL,
            standaloneListURL: StandaloneList.defaultURL,
            lookup: ReleaseLookup(transport: transport),
            detector: InstalledVersionDetector(),
            downloader: ReleaseDownloader(transport: transport),
            vault: CredentialVault(store: KeychainSecretStore()),
            revealer: FinderRevealer(),
            now: { Date() })
    }
}
