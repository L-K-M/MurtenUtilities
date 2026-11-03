import Foundation
import ShortkingCore
import ShortkingKit

/// Shortking's preferences inside the suite: the source's `AppSettings`,
/// JSON-encoded under one key of the module's defaults (`ModuleContext.defaults`).
///
/// The standalone app keeps them in `~/Library/Application Support/Shortking/
/// settings.json`. The first load imports that file read-only, so the user's
/// scan scope, probe breadth and learning choice carry over; the file is never
/// written, and the standalone app keeps using it. Onboarding does not carry
/// over: Accessibility and Input Monitoring now belong to Murten Utilities,
/// which has to be granted them itself, and onboarding is where that happens.
@MainActor
final class ShortkingSettingsStore {

    static let key = "settings"

    private let defaults: UserDefaults
    private(set) var current: AppSettings

    /// - Parameter legacyFile: the standalone app's `settings.json`, read once
    ///   when the defaults hold nothing yet.
    init(defaults: UserDefaults, legacyFile: URL?) {
        self.defaults = defaults
        if let stored = Self.stored(in: defaults) {
            current = stored
            return
        }

        var initial = legacyFile.flatMap(Self.imported(from:)) ?? AppSettings()
        initial.hasCompletedOnboarding = false
        current = initial
        save()
    }

    func update(_ transform: (inout AppSettings) -> Void) {
        transform(&current)
        save()
    }

    // MARK: - Persistence

    private func save() {
        do {
            defaults.set(try Self.encoder.encode(current), forKey: Self.key)
        } catch {
            Log.store.error("Failed to save settings: \(error.localizedDescription)")
        }
    }

    private static func stored(in defaults: UserDefaults) -> AppSettings? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try decoder.decode(AppSettings.self, from: data)
        } catch {
            // Only this module writes the key, so this is a bug, not user data
            // worth keeping: say so and start from the defaults.
            Log.store.error("Stored settings are unreadable, using defaults: \(error.localizedDescription)")
            return nil
        }
    }

    private static func imported(from file: URL) -> AppSettings? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            return try StoreFileReader.payload(AppSettings.self, from: Data(contentsOf: file))
        } catch {
            Log.store.warning("Did not import \(file.path): \(String(describing: error))")
            return nil
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
