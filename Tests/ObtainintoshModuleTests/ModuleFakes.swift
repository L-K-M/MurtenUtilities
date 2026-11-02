import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import MurtenModuleKit
import ObtainintoshCore
@testable import ObtainintoshModule
@testable import ObtainintoshServices

/// Releases by repository URL; records what was asked and with which key.
final class FixtureLookup: ReleaseLooking, @unchecked Sendable {
    private let lock = NSLock()
    var releases: [String: Result<Release, Error>] = [:]
    private var asked: [(url: String, key: String?)] = []

    var lookups: [(url: String, key: String?)] { lock.withLock { asked } }

    func latestRelease(of app: TrackedApp, credentials: LookupCredentials, budget: RequestBudget?) async throws -> Release {
        let result: Result<Release, Error>? = lock.withLock {
            asked.append((app.sourceURL, credentials.forge.token))
            return releases[app.sourceURL]
        }
        guard let result else { throw LookupFailure(.failed, "no fixture for \(app.sourceURL)") }
        return try result.get()
    }

    func releasePrograms(for input: SourceInput, credentials: LookupCredentials) async throws -> ReleasePrograms {
        ReleasePrograms(version: "1.0", programs: [], defaultProgram: nil)
    }

    func downloadAuth(for app: TrackedApp, credentials: LookupCredentials) throws -> DownloadAuth? { nil }
}

/// Installed versions by program name.
struct FixtureDetector: InstalledVersionDetecting {
    var installed: [String: InstalledVersion] = [:]

    func detectPrograms(_ apps: [TrackedApp]) async -> [InstalledVersion?] {
        apps.map { installed[$0.name] }
    }

    func detectFonts(_ lookups: [FontLookup?]) async -> [FontDetection] {
        lookups.map { _ in .notAFont }
    }
}

/// Serves every download as `bytes` bytes.
struct FixedTransport: HTTPTransport {
    let bytes: Int

    func stream(_ request: URLRequest) async throws -> HTTPStream {
        let body = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data(repeating: 1, count: bytes))
            continuation.finish()
        }
        return HTTPStream(status: 200, headers: [:], body: body)
    }
}

final class RecordingRevealer: FileRevealing, @unchecked Sendable {
    private(set) var revealed: [URL] = []

    @MainActor func reveal(_ url: URL) -> Bool {
        revealed.append(url)
        return true
    }
}

/// Secrets in memory, counting reads.
final class MemorySecrets: SecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]
    private var readCount = 0

    init(_ values: [String: String] = [:]) {
        self.values = values
    }

    var reads: Int { lock.withLock { readCount } }
    var stored: [String: String] { lock.withLock { values } }

    func read(account: String) throws -> String? {
        lock.withLock {
            readCount += 1
            return values[account]
        }
    }

    func write(_ value: String, account: String) throws { lock.withLock { values[account] = value } }
    func delete(account: String) throws { lock.withLock { values[account] = nil } }
}

/// A module environment in a scratch folder.
@MainActor
final class Fixture {
    let folder: URL
    let lookup = FixtureLookup()
    let secrets: MemorySecrets
    let revealer = RecordingRevealer()
    let defaults: UserDefaults
    var detector = FixtureDetector()

    init(secrets: [String: String] = [:]) {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("obtainintosh-module-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.secrets = MemorySecrets(secrets)
        defaults = UserDefaults(suiteName: "ObtainintoshModuleTests.\(UUID().uuidString)")!
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    var listURL: URL { folder.appendingPathComponent("Suite/apps.json") }
    var standaloneURL: URL { folder.appendingPathComponent("Standalone/apps.json") }

    func environment() -> ObtainintoshEnvironment {
        ObtainintoshEnvironment(
            listURL: listURL, standaloneListURL: standaloneURL, lookup: lookup, detector: detector,
            downloader: ReleaseDownloader(transport: FixedTransport(bytes: 10),
                                          cacheRoot: folder.appendingPathComponent("Downloads")),
            vault: CredentialVault(store: secrets), revealer: revealer,
            now: { Date(timeIntervalSince1970: 1_800_000_000) })
    }

    /// How often the model asked the suite to run the background check.
    private(set) var recheckRequests = 0

    func model() -> ObtainintoshModel {
        ObtainintoshModel(environment: environment(), defaults: defaults,
                          requestRecheck: { [weak self] in self?.recheckRequests += 1 })
    }

    func context() -> ModuleContext {
        ModuleContext(moduleID: "obtainintosh", defaults: defaults, requestRecheck: {}, open: { _ in })
    }

    func writeStandalone(_ json: String) {
        try? FileManager.default.createDirectory(at: standaloneURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: standaloneURL.path, contents: Data(json.utf8))
    }
}
