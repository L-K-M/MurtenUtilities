import Foundation
import DoctorCore
import MurtenCore

/// DeviceControlDoctor's background check: for every app on the watch list,
/// the permission records of its expected services (`tccutil list`) and its
/// signing identity (`codesign`) against the baseline the pane saved.
///
/// It only observes. It reads the watch list in place and never writes it,
/// never resets a permission, never quits or opens an app, needs no
/// privilege and raises no prompt: apps in privacy-guarded folders are left
/// to the pane. Every app is a scope; one that could not be read fully is
/// reported as a failure, never as healthy.
struct PermissionWatcher: Watcher {
    /// Permission drift follows app updates, which are rare; each poll spawns
    /// a few processes per app.
    static let interval: TimeInterval = 30 * 60
    /// Two codesign runs per app, up to 8 s each when a large bundle is slow.
    static let timeout: TimeInterval = 120

    let moduleID = DoctorRoute.moduleID
    let cadence = WatchCadence(interval: PermissionWatcher.interval, timeout: PermissionWatcher.timeout)

    private let watchList: URL
    private let runner: any ProcessRunning
    private let home: String
    private let now: @Sendable () -> Date
    private let history = ScopeHistory()

    init(watchList: URL, runner: any ProcessRunning,
         home: String = FileManager.default.homeDirectoryForCurrentUser.path,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.watchList = watchList
        self.runner = runner
        self.home = home
        self.now = now
    }

    func observe() async -> WatchObservation {
        let started = now()

        let apps: [WatchedApp]
        switch WatchListFile.read(at: watchList) {
        case .missing:
            apps = []
        case .loaded(let state):
            apps = state.apps
        case .unreadable:
            return .unavailable(moduleID: moduleID, at: started, ObservationFailure(
                kind: .malformedResponse,
                message: "The watch list could not be read. Open DeviceControlDoctor for details."))
        }

        var findings: [Finding] = []
        var completed = Set<FindingScope>()
        var failures: [ObservationFailure] = []
        var listing: Bool?

        for app in apps {
            let scope = VerificationFinding.scope(for: app.id)
            switch await read(app, listing: &listing) {
            case .cancelled:
                return .unavailable(moduleID: moduleID, at: started,
                                    ObservationFailure(kind: .failed, message: "The check was cancelled."))
            case .skipped(let kind, let message):
                failures.append(ObservationFailure(kind: kind, scope: scope, message: "\(app.name): \(message)"))
            case .read(let reading):
                let assessment = VerificationAssessment(app: app, reading: reading)
                if let finding = VerificationFinding.make(app: app, assessment: assessment, at: now()) {
                    findings.append(finding)
                }
                failures += assessment.gaps.map {
                    ObservationFailure(kind: $0.kind, scope: scope, message: "\(app.name): \($0.message)")
                }
                if assessment.isComplete { completed.insert(scope) }
            }
        }

        // An app removed from the list was checked and is absent.
        completed.formUnion(history.retire(keeping: Set(apps.map { VerificationFinding.scope(for: $0.id) })))
        return WatchObservation(moduleID: moduleID, observedAt: started, findings: findings,
                                completedScopes: completed, failures: failures)
    }

    // MARK: - One app

    private enum AppCheck {
        case read(WatchedAppReading)
        case skipped(ObservationFailure.Kind, String)
        case cancelled
    }

    /// The same reads as the pane's check, limited to the expected services.
    /// `listing` caches whether this Mac offers `tccutil list`, probed once
    /// and only when an app needs it.
    private func read(_ app: WatchedApp, listing: inout Bool?) async -> AppCheck {
        guard !Task.isCancelled else { return .cancelled }

        // Resolved without looking inside a guarded folder, and then used for
        // every read, so a link added later cannot lead a read into one.
        guard let path = ProtectedLocation.readablePath(app.path, home: home, linkDestination: Self.linkDestination) else {
            return .skipped(.permissionDenied,
                            "It is in a folder macOS protects, so it is checked only when you open DeviceControlDoctor.")
        }
        let clientIdentifier = app.canReset ? nil : app.bundleID
        guard let current = AppCatalog.app(at: URL(fileURLWithPath: path), clientIdentifier: clientIdentifier) else {
            return .skipped(.toolMissing, "It is missing at \(app.path).")
        }
        if app.canReset && current.bundleID != app.bundleID {
            return .skipped(.failed, "The app at \(app.path) now has a different bundle identifier.")
        }

        var permissions: [PermissionService: AuthorizationResult]? = [:]
        if !app.expectedServices.isEmpty {
            if listing == nil {
                let help = await runner.run(SystemTool.tccutil, [])
                guard !Task.isCancelled else { return .cancelled }
                listing = !help.timedOut && TCCOutputParser.supportsListing(help: help.output)
            }
            if listing == true {
                for service in app.expectedServices {
                    let command = await runner.run(SystemTool.tccutil, ["list", "-s", service.rawValue, "-b", app.bundleID])
                    guard !Task.isCancelled else { return .cancelled }
                    permissions?[service] = command.timedOut
                        ? AuthorizationResult(state: .unknown, detail: "The permission query timed out.")
                        : TCCOutputParser.parseQuery(output: command.output, exitCode: command.exitCode)
                }
            } else {
                permissions = nil
            }
        }

        // Without a finished baseline check there is nothing to compare a
        // new signature against, so codesign would be wasted work.
        guard app.identity.signatureValid != nil else {
            return .read(WatchedAppReading(permissions: permissions, identity: AppIdentity()))
        }
        let identity = await IdentityInspector(runner: runner).inspect(path: path)
        guard !Task.isCancelled else { return .cancelled }
        return .read(WatchedAppReading(permissions: permissions, identity: identity))
    }

    /// The target of `path` when that one entry is a symbolic link (`lstat`,
    /// then `readlink`); nil otherwise. Never follows the link.
    private static func linkDestination(_ path: String) -> String? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        guard attributes?[.type] as? FileAttributeType == .typeSymbolicLink else { return nil }
        return try? FileManager.default.destinationOfSymbolicLink(atPath: path)
    }

    // MARK: - Removed apps

    /// The scopes the previous poll saw on the list, so a removed app's
    /// suggestion resolves instead of lingering. The contract has no way to
    /// retire a scope and a watcher persists nothing, so this memory starts
    /// empty at launch: an app removed while the suite was not running keeps
    /// its suggestion until the user dismisses it.
    private final class ScopeHistory: @unchecked Sendable {
        private let lock = NSLock()
        private var previous: Set<FindingScope> = []

        /// Remembers `current`; returns the scopes that left the list since the last call.
        func retire(keeping current: Set<FindingScope>) -> Set<FindingScope> {
            lock.lock(); defer { lock.unlock() }
            let removed = previous.subtracting(current)
            previous = current
            return removed
        }
    }
}
