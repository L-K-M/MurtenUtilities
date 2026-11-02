import Foundation
import ObtainintoshCore

/// The standalone Obtainintosh app's tracked list. The suite only ever reads
/// it, when the user asks to import it: no permission change, no backup, no
/// write, so the standalone app keeps working exactly as before.
public enum StandaloneList {
    /// `~/Library/Application Support/Obtainintosh/apps.json`.
    public static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Obtainintosh/apps.json")
    }

    /// Whether a list is there to offer for import.
    public static func exists(at url: URL = defaultURL) -> Bool {
        (try? TrackedListStore.readSnapshotAttributes(url)) == true
    }

    /// The list with its plain-text tokens, which the caller moves into the
    /// Keychain.
    public static func read(at url: URL = defaultURL) throws -> TrackedAppData {
        do {
            guard let data = try TrackedListStore.readSnapshot(at: url) else {
                throw ObtainintoshError("The Obtainintosh app's program list was not found at \(url.path)")
            }
            return data
        } catch let error as ObtainintoshError {
            throw error
        } catch {
            throw ObtainintoshError("The Obtainintosh app's program list could not be read: \(error.localizedDescription)")
        }
    }
}
