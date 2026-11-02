import Foundation

/// What a check reported about one program. `skipped` covers a result that
/// could not be applied because the program moved out from under it.
public struct CheckOutcome: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case succeeded
        case failed
        case unsupported
        case skipped
    }

    public let appID: String
    public let appName: String
    public let state: State
    public let message: String?

    public init(appID: String, appName: String, state: State, message: String? = nil) {
        self.appID = appID
        self.appName = appName
        self.state = state
        self.message = message
    }

    /// The outcome of applying a result to the store.
    public static func make(for app: TrackedApp, update: CheckOwnedUpdate,
                            application: PendingResultApplication) -> CheckOutcome {
        switch application {
        case .appRemoved:
            return CheckOutcome(appID: app.id, appName: app.name, state: .skipped,
                                message: "The program was removed while its update check was running")
        case .dependenciesChanged:
            return CheckOutcome(appID: app.id, appName: app.name, state: .skipped,
                                message: "The program changed while its update check was running, so the result "
                                    + "was discarded")
        case .applied:
            switch update.attempt.state {
            case .succeeded: return CheckOutcome(appID: app.id, appName: app.name, state: .succeeded)
            case .failed:
                return CheckOutcome(appID: app.id, appName: app.name, state: .failed, message: update.attempt.message)
            case .unsupported:
                return CheckOutcome(appID: app.id, appName: app.name, state: .unsupported,
                                    message: update.attempt.message)
            }
        }
    }

    /// One line summarising what a check run did not manage to do, or nil
    /// when everything succeeded.
    public static func failureSummary(_ outcomes: [CheckOutcome]) -> String? {
        let incomplete = outcomes.filter { $0.state != .succeeded }
        guard let first = incomplete.first else { return nil }

        if incomplete.count == 1 {
            return "\(first.appName): \(ProgramStatus.nonEmpty(first.message) ?? "The update check did not complete")"
        }
        if incomplete.count == outcomes.count {
            return "Update checks failed or were skipped for all \(outcomes.count) apps"
        }
        return "\(incomplete.count) of \(outcomes.count) update checks failed or were skipped"
    }
}
