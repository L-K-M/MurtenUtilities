import Foundation
import Observation
import ObtainintoshCore
import ObtainintoshServices

/// The pane's state and every action of the standalone app's window: add,
/// edit, remove, check, download, reveal, export, import and settings. The
/// provider owns one for the app's lifetime, so a check or download keeps
/// going while the user is elsewhere in the suite.
@MainActor
@Observable
final class ObtainintoshModel {
    // MARK: - State types

    /// Progress of a check, as the standalone app's dialog showed it:
    /// `position - 1` programs are finished, `appName` is one still running.
    struct CheckProgress: Equatable {
        var position: Int
        var total: Int
        var appName: String
    }

    struct DownloadProgress: Equatable {
        var appID: String
        var fileName: String
        var downloaded: UInt64
        var total: UInt64
    }

    /// A non-modal message, the counterpart of the standalone app's
    /// notifications. Errors stay until dismissed.
    struct Notice: Identifiable, Equatable {
        enum Kind {
            case success
            case info
            case error
        }

        let id = UUID()
        let text: String
        let kind: Kind
    }

    /// The user's answer to the standalone list's import offer, kept in the
    /// module's preferences.
    enum StandaloneImportDecision: String {
        case imported
        case declined
    }

    static let standaloneImportKey = "standaloneImport"
    /// How many release lookups run at once during a check.
    static let checkConcurrency = 4

    // MARK: - Observed state

    private(set) var apps: [TrackedApp] = []
    private(set) var isLoaded = false
    private(set) var isChecking = false
    private(set) var checkProgress: CheckProgress?
    private(set) var downloadProgress: DownloadProgress?
    /// From the click until the download ends, including the release lookup
    /// before the first byte, when `downloadProgress` is still nil.
    private(set) var isDownloading = false
    private(set) var notices: [Notice] = []
    /// A problem with the list itself, shown above the table.
    var errorBanner: String?
    /// The table's sort, kept here so it survives navigating away.
    var sortOrder = [ProgramComparator(field: .name)]
    /// How many programs the standalone app's list holds, while its import
    /// is on offer.
    private(set) var standaloneOffer: Int?

    // MARK: - Collaborators

    @ObservationIgnored private var store: TrackedListStore?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    /// Bumped per download, so a late progress report of an earlier one is dropped.
    @ObservationIgnored private var downloadGeneration = 0
    @ObservationIgnored private var hasCheckedThisSession = false
    @ObservationIgnored private var finished: [Bool] = []

    private let environment: ObtainintoshEnvironment
    private let defaults: UserDefaults
    /// Asks the suite to run the background check soon, so a suggestion
    /// that a check or a removal settled resolves without waiting hours.
    private let requestRecheck: @MainActor () -> Void
    private let downloadSlot = DownloadSlot()

    init(environment: ObtainintoshEnvironment, defaults: UserDefaults,
         requestRecheck: @escaping @MainActor () -> Void = {}) {
        self.environment = environment
        self.defaults = defaults
        self.requestRecheck = requestRecheck
    }

    var isBusy: Bool { isChecking || isDownloading }

    /// Why quitting now would lose work.
    var interruptionWarning: String? {
        if isDownloading { return "A download is still running." }
        if isChecking { return "An update check is still running." }
        return nil
    }

    // MARK: - Opening

    /// The pane appeared: load the list and, the first time this session or
    /// when a suggestion opened it, check quietly, as the standalone app did
    /// when it started. A route never starts a download.
    func paneAppeared(route action: String?) {
        load()
        refreshStandaloneOffer()
        let opensUpdates = action == UpdateFinding.routeAction
        guard store != nil, !isChecking, !hasCheckedThisSession || opensUpdates else { return }
        hasCheckedThisSession = true
        // Owned by the model, not the view: leaving the pane must not cancel it.
        Task { await checkForUpdates(quiet: true) }
    }

    /// Reads the list, opening the store the first time. A downloaded file
    /// the system cleared from the temporary folder is forgotten, so the
    /// row offers the download again.
    func load() {
        // A failed open leaves no store and is retried here; its banner must
        // not outlive a retry that succeeds. A recovery banner set while
        // opening stays.
        if store == nil { errorBanner = nil }
        do {
            let store = try openStore()
            let vanished = store.apps.filter { app in
                guard let path = app.downloaded?.path else { return false }
                var isDirectory: ObjCBool = false
                return !FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) || isDirectory.boolValue
            }.map(\.id)
            if !vanished.isEmpty {
                // Bookkeeping only: a failure here must not fail the load.
                _ = try? store.forgetDownloads(vanished)
            }
            apps = store.apps
            isLoaded = true
        } catch {
            errorBanner = "The program list could not be opened: \(error.localizedDescription)"
        }
    }

    private func openStore() throws -> TrackedListStore {
        if let store { return store }
        let opened = try TrackedListStore(fileURL: environment.listURL)
        if case .recovered(let backup, let reason) = opened.loadOutcome {
            errorBanner = "The program list could not be read (\(reason)). It was kept at \(backup.path), and the "
                + "list starts empty."
        }
        store = opened
        return opened
    }

    // MARK: - Adding, editing, removing

    /// Adds a program; throws a message for the dialog.
    func add(_ input: SourceInput) async throws {
        let store = try openStore()
        var app = try input.makeApp()
        let key = app.accessToken
        app.accessToken = nil
        if let installed = await environment.detector.detectPrograms([app]).first ?? nil {
            app.currentVersion = installed.version
            app.installPath = installed.path
        }

        var added = try store.addOne(app)
        if let key {
            do {
                try await environment.vault.setToken(key, for: .forgejo(appID: added.id))
                added.hasStoredAccessToken = true
                try store.update(added)
            } catch {
                post("\"\(added.name)\" was added, but its application key could not be saved: "
                     + error.localizedDescription, .error)
            }
        }
        apps = store.apps
        post("App \"\(input.name)\" added successfully", .success)
    }

    /// Applies the edit dialog; throws a message for the dialog.
    func update(id: String, with input: SourceInput) async throws {
        let store = try openStore()
        guard let app = store.app(id: id) else { throw ObtainintoshError("App not found") }
        var updated = try input.applied(to: app)
        let key = updated.accessToken
        updated.accessToken = nil

        // Credentials come from the dialog every time: a cleared field, or a
        // source that sends none, removes the stored key.
        try await environment.vault.setToken(key, for: .forgejo(appID: id))
        updated.hasStoredAccessToken = key != nil
        try store.update(updated)
        apps = store.apps
    }

    func remove(id: String) async {
        guard let store = try? openStore(), let app = store.app(id: id) else { return }
        do {
            try store.remove(id: id)
            apps = store.apps
            post("\"\(app.name)\" removed", .success)
            requestRecheck()
        } catch {
            post("Failed to remove app: \(error.localizedDescription)", .error)
            return
        }
        if app.hasStoredAccessToken {
            do {
                try await environment.vault.setToken(nil, for: .forgejo(appID: id))
            } catch {
                post("The application key of \"\(app.name)\" could not be removed from the Keychain: "
                     + error.localizedDescription, .error)
            }
        }
    }

    /// The stored key for the edit dialog. Reading may show the Keychain's
    /// prompt, so it happens only when the user opens the dialog.
    func accessToken(for app: TrackedApp) async -> String? {
        guard app.hasStoredAccessToken else { return nil }
        do {
            return try await environment.vault.token(.forgejo(appID: app.id))
        } catch {
            post(error.localizedDescription, .error)
            return nil
        }
    }

    /// The programs a repository's latest release offers, for the dialog.
    /// Uses a GitHub token only if this session already read it, so typing
    /// a URL never raises a Keychain prompt.
    func releasePrograms(for input: SourceInput) async throws -> ReleasePrograms {
        let credentials = LookupCredentials(gitHubToken: await environment.vault.cachedToken(.gitHub),
                                            forge: input.credentials(for: try input.resolvedSourceType()))
        return try await environment.lookup.releasePrograms(for: input, credentials: credentials)
    }

    // MARK: - Checking

    /// Checks every program, or one: re-detects installed versions, looks
    /// up releases four at a time, and writes back only the fields a check
    /// owns, only if the program did not change meanwhile.
    func checkForUpdates(quiet: Bool = false) async {
        guard !isChecking, let store = try? openStore() else { return }
        hasCheckedThisSession = true
        isChecking = true
        checkProgress = nil
        defer {
            isChecking = false
            checkProgress = nil
            apps = store.apps
            // Installed versions may have changed since the last poll.
            requestRecheck()
        }

        let snapshots = store.apps
        guard !snapshots.isEmpty else {
            if !quiet { post("Update check completed", .success) }
            return
        }
        let installed = await environment.detector.detectPrograms(snapshots)
        let gitHubToken = snapshots.contains { $0.sourceType == .github } ? await readToken(.gitHub) : nil
        var credentials: [LookupCredentials] = []
        for app in snapshots {
            var forge = ForgeCredentials()
            if app.sourceType == .forgejo {
                let key = app.hasStoredAccessToken ? await readToken(.forgejo(appID: app.id)) : nil
                forge = ForgeCredentials(username: app.username, token: key)
            }
            credentials.append(LookupCredentials(gitHubToken: gitHubToken, forge: forge))
        }

        finished = Array(repeating: false, count: snapshots.count)
        checkProgress = CheckProgress(position: 1, total: snapshots.count, appName: snapshots[0].name)
        let lookup = environment.lookup
        let jobs = Array(zip(snapshots, credentials).enumerated())
        let results = await boundedOrderedMap(jobs, limit: Self.checkConcurrency) { job -> Result<Release, Error> in
            let (index, (app, credentials)) = job
            let result: Result<Release, Error>
            do {
                result = .success(try await lookup.latestRelease(of: app, credentials: credentials, budget: nil))
            } catch {
                result = .failure(error)
            }
            await self.markFinished(index, names: snapshots.map(\.name))
            return result
        }

        // A font found by the release's file name replaces the program
        // detection; when the lookup failed, the copy found last time is read.
        let fontLookups: [FontLookup?] = zip(results, snapshots).map { result, snapshot in
            if case .success(let release) = result {
                return FontFile.isFontFile(release.fileName) ? .named(release.fileName) : nil
            }
            guard let path = snapshot.installPath, FontFile.isFontFile(path) else { return nil }
            return .lastFoundAt(path)
        }
        let fonts = await environment.detector.detectFonts(fontLookups)

        let attemptedAt = Self.timestamp(environment.now())
        var outcomes: [CheckOutcome] = []
        for index in snapshots.indices {
            let snapshot = snapshots[index]
            var copy = installed[index]
            switch fonts[index] {
            case .notAFont: break
            case .installed(let font): copy = font
            case .notInstalled: copy = nil
            }
            let update = CheckOwnedUpdate.from(installed: copy, sourceType: snapshot.sourceType, result: results[index],
                                               attemptedAt: attemptedAt)
            do {
                let application = try store.applyCheckResult(snapshot: snapshot, update: update)
                outcomes.append(CheckOutcome.make(for: snapshot, update: update, application: application))
            } catch {
                outcomes.append(CheckOutcome(appID: snapshot.id, appName: snapshot.name, state: .failed,
                                             message: boundedCheckMessage("Could not save the update check: "
                                                + error.localizedDescription)))
            }
        }

        // Shown even when quiet: a check that silently did nothing is what
        // this is meant to stop.
        if let summary = CheckOutcome.failureSummary(outcomes) {
            post(summary, .error)
        } else if !quiet {
            post("Update check completed", .success)
        }
    }

    private func markFinished(_ index: Int, names: [String]) {
        guard index < finished.count, let progress = checkProgress else { return }
        finished[index] = true
        let done = finished.filter { $0 }.count
        let outstanding = finished.firstIndex(of: false) ?? index
        checkProgress = CheckProgress(position: min(done + 1, progress.total), total: progress.total,
                                      appName: names[outstanding])
    }

    /// A token for an action the user started; a failure is reported and
    /// the action goes on without it.
    private func readToken(_ account: CredentialVault.Account) async -> String? {
        do {
            return try await environment.vault.token(account)
        } catch {
            post(error.localizedDescription, .error)
            return nil
        }
    }

    // MARK: - Downloading

    /// Downloads the latest release into the temporary cache and shows it
    /// in Finder. One download at a time; it can be cancelled.
    func download(id: String) {
        guard let store = try? openStore(), let app = store.app(id: id) else { return }
        let lease: DownloadSlot.Lease
        do {
            lease = try downloadSlot.acquire("\(app.name) (\(app.id))")
        } catch {
            post(error.localizedDescription, .error)
            return
        }
        isDownloading = true
        downloadGeneration += 1
        let generation = downloadGeneration
        downloadTask = Task {
            await self.runDownload(app, store: store, generation: generation)
            lease.release()
            self.downloadProgress = nil
            self.downloadTask = nil
            self.isDownloading = false
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    private func runDownload(_ app: TrackedApp, store: TrackedListStore, generation: Int) async {
        do {
            var credentials = LookupCredentials()
            if app.sourceType == .github { credentials.gitHubToken = await readToken(.gitHub) }
            if app.sourceType == .forgejo {
                let key = app.hasStoredAccessToken ? await readToken(.forgejo(appID: app.id)) : nil
                credentials.forge = ForgeCredentials(username: app.username, token: key)
            }
            let release = try await environment.lookup.latestRelease(of: app, credentials: credentials, budget: nil)
            let auth = try environment.lookup.downloadAuth(for: app, credentials: credentials)
            downloadProgress = DownloadProgress(appID: app.id, fileName: release.fileName, downloaded: 0,
                                                total: release.fileSize ?? 0)

            let file = try await environment.downloader.download(
                release,
                auth: auth,
                appKey: app.id
            ) { [self] done, total in
                Task { @MainActor [weak self] in
                    guard let self, self.downloadGeneration == generation else { return }
                    self.showDownloadProgress(done, of: total)
                }
            }

            let revealed = environment.revealer.reveal(file)
            let revealMessage = revealed
                ? "The file was revealed in Finder. Please double-click it to install."
                : "The file could not be revealed in Finder. Please open its containing folder manually."

            // Recorded even before a first check, so the row shows the
            // release just fetched and offers to show it again.
            if var current = store.app(id: app.id) {
                current.lastChecked = Self.timestamp(environment.now())
                current.latestVersion = release.version
                current.downloaded = DownloadedRelease(version: release.version, path: file.path)
                try store.update(current)
            }
            apps = store.apps
            post("Download finished: \(file.path)\n\n\(revealMessage)", .success)
        } catch is CancellationError {
            post("The download of \(app.name) was cancelled.", .info)
        } catch {
            post(error.localizedDescription, .error)
        }
    }

    private func showDownloadProgress(_ done: UInt64, of total: UInt64) {
        guard var progress = downloadProgress, done >= progress.downloaded else { return }
        progress.downloaded = done
        progress.total = total
        downloadProgress = progress
    }

    /// Shows the cached file of the latest version in Finder, or forgets it
    /// when the system cleared it from the temporary folder.
    func revealDownload(id: String) {
        guard let store = try? openStore(), let app = store.app(id: id), let downloaded = app.downloaded else {
            post("No downloaded file is recorded for this program", .error)
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: downloaded.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            _ = try? store.forgetDownloads([id])
            apps = store.apps
            post("The downloaded file for version \(downloaded.version) is no longer on disk — the download folder "
                 + "is temporary and may have been cleared. Download it again.", .error)
            return
        }
        if environment.revealer.reveal(URL(fileURLWithPath: downloaded.path)) {
            post("The file for version \(downloaded.version) was revealed in Finder.", .success)
        } else {
            post("The file could not be revealed in Finder.", .error)
        }
    }

    // MARK: - Export and import

    /// The file contents, made before the save panel opens so a failure
    /// never asks for a path first.
    func exportContents() -> String? {
        guard !apps.isEmpty else {
            post("There are no programs to export", .error)
            return nil
        }
        do {
            return try AppList.render(apps, exportedAt: Self.timestamp(environment.now()),
                                      exportedBy: ObtainintoshUserAgent.value)
        } catch {
            post(error.localizedDescription, .error)
            return nil
        }
    }

    func writeExport(_ contents: String, to chosen: URL) {
        let url = AppList.withDefaultExtension(chosen)
        do {
            if url == chosen {
                // The panel confirmed replacing this exact name.
                try Data(contents.utf8).write(to: url, options: .atomic)
            } else if FileManager.default.fileExists(atPath: url.path) {
                // The panel asked about the typed name, not the one with the
                // extension added; a file there was never agreed to be replaced.
                post("A file named \(AppList.displayName(url)) already exists there. Choose another name.", .error)
                return
            } else {
                try Data(contents.utf8).write(to: url, options: .withoutOverwriting)
            }
            post("Exported \(ImportSummary.plural(apps.count, "program")) to \(AppList.displayName(url))", .success)
        } catch {
            post("The program list could not be written: \(error.localizedDescription)", .error)
        }
    }

    /// Merges a program-list file into the list; adds only, never removes.
    func importList(from url: URL) async {
        let name = AppList.displayName(url)
        let entries: [ExportedApp]
        do {
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value ?? 0
            guard size <= AppList.maximumFileSize else {
                post("\(name) is too large to be a program list (the limit is "
                     + "\(AppList.maximumFileSize / (1024 * 1024)) MB)", .error)
                return
            }
            let contents = try String(contentsOf: url, encoding: .utf8)
            entries = try AppList.parse(contents)
        } catch let error as ObtainintoshError {
            post("\(name): \(error.message)", .error)
            return
        } catch {
            post("\(name) could not be read: \(error.localizedDescription)", .error)
            return
        }

        let plan = AppList.planImport(entries)
        guard let addition = await addBatch(plan.apps) else { return }
        let missingKeys = addition.added.filter(AppList.isMissingApplicationKey).count
        let summary = ImportSummary(fileName: name, added: addition.added.count, duplicates: addition.duplicates.count,
                                    rejected: plan.rejected, missingKeys: missingKeys)
        report(summary)
        // Newly imported programs have no release information yet.
        if !addition.added.isEmpty { await checkForUpdates(quiet: true) }
    }

    // MARK: - The standalone app's list

    var offersStandaloneImport: Bool { standaloneOffer != nil }

    func refreshStandaloneOffer() {
        guard defaults.string(forKey: Self.standaloneImportKey) == nil,
              StandaloneList.exists(at: environment.standaloneListURL),
              let data = try? StandaloneList.read(at: environment.standaloneListURL) else {
            standaloneOffer = nil
            return
        }
        standaloneOffer = data.apps.count
    }

    var standaloneListExists: Bool { StandaloneList.exists(at: environment.standaloneListURL) }

    /// Copies the standalone app's programs into the suite's list and its
    /// tokens into the Keychain. The standalone app's file is only read.
    func importStandaloneList() async {
        let data: TrackedAppData
        do {
            data = try StandaloneList.read(at: environment.standaloneListURL)
        } catch {
            post(error.localizedDescription, .error)
            return
        }

        if let token = data.settings.githubToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            // A token the Keychain would not hand over is still a token: it
            // is kept, not replaced by the standalone app's.
            do {
                if try await environment.vault.token(.gitHub) == nil {
                    try await environment.vault.setToken(token, for: .gitHub)
                }
            } catch {
                post("The GitHub token was not imported: \(error.localizedDescription)", .error)
            }
        }

        guard let addition = await addBatch(data.apps) else { return }
        defaults.set(StandaloneImportDecision.imported.rawValue, forKey: Self.standaloneImportKey)
        standaloneOffer = nil
        report(ImportSummary(fileName: "the Obtainintosh app", added: addition.added.count,
                             duplicates: addition.duplicates.count))
        if !addition.added.isEmpty { await checkForUpdates(quiet: true) }
    }

    func declineStandaloneImport() {
        defaults.set(StandaloneImportDecision.declined.rawValue, forKey: Self.standaloneImportKey)
        standaloneOffer = nil
    }

    /// Adds programs in one write and moves their keys into the Keychain.
    /// Installed versions are detected first, so they show at once; the
    /// keys are matched back by what each entry tracks.
    private func addBatch(_ incoming: [TrackedApp]) async -> TrackedAppList.BatchAddition? {
        let store: TrackedListStore
        do {
            store = try openStore()
        } catch {
            post(error.localizedDescription, .error)
            return nil
        }

        let installed = await environment.detector.detectPrograms(incoming)
        var keys: [TrackedAppList.TrackingKey: String] = [:]
        var prepared: [TrackedApp] = []
        for (app, copy) in zip(incoming, installed) {
            var entry = app
            let credentials = ForgeCredentials.forSource(app.sourceType, username: app.username, token: app.accessToken)
            let trackingKey = TrackedAppList.trackingKey(app)
            if let token = credentials.token, keys[trackingKey] == nil { keys[trackingKey] = token }
            entry.accessToken = nil
            entry.hasStoredAccessToken = false
            if let copy {
                entry.currentVersion = copy.version
                entry.installPath = copy.path
            }
            prepared.append(entry)
        }

        var addition: TrackedAppList.BatchAddition
        do {
            addition = try store.add(prepared)
        } catch {
            post(error.localizedDescription, .error)
            return nil
        }

        for (offset, app) in addition.added.enumerated() {
            guard let key = keys[TrackedAppList.trackingKey(app)] else { continue }
            do {
                try await environment.vault.setToken(key, for: .forgejo(appID: app.id))
                var stored = app
                stored.hasStoredAccessToken = true
                try store.update(stored)
                addition.added[offset] = stored
            } catch {
                post("The application key of \"\(app.name)\" could not be saved: \(error.localizedDescription)", .error)
            }
        }
        apps = store.apps
        return addition
    }

    private func report(_ summary: ImportSummary) {
        post(summary.message, summary.added > 0 ? .success : .info)
        if let missing = summary.missingKeysMessage { post(missing, .info) }
        if let rejected = summary.rejectedMessage { post(rejected, .error) }
    }

    // MARK: - Settings

    /// The stored GitHub token, for the settings form. Reading may prompt.
    func gitHubToken() async -> String? {
        await readToken(.gitHub)
    }

    func saveGitHubToken(_ token: String?) async throws {
        try await environment.vault.setToken(token, for: .gitHub)
    }

    // MARK: - Notices

    func post(_ text: String, _ kind: Notice.Kind) {
        notices.append(Notice(text: text, kind: kind))
    }

    func dismiss(_ notice: Notice) {
        notices.removeAll { $0.id == notice.id }
    }

    static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
