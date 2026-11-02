import Foundation
import MurtenCore

/// What a background check read for one watched app, before judging it.
public struct WatchedAppReading: Sendable {
    /// Results for the app's expected permissions, or nil when this Mac
    /// cannot list permission records (`tccutil list` is missing).
    public var permissions: [PermissionService: AuthorizationResult]?
    /// The current signing identity; `signatureValid` is nil when the
    /// signature check did not finish.
    public var identity: AppIdentity

    public init(permissions: [PermissionService: AuthorizationResult]?, identity: AppIdentity) {
        self.permissions = permissions
        self.identity = identity
    }
}

/// Whether a watched app should be verified again, judged from cheap
/// signals only: the permission record macOS reports and the app's signing
/// identity against the saved baseline. Neither proves that the app works
/// or fails, so the strongest conclusion is "verify again".
///
/// Errors are not denials: a query that timed out, an unparsable answer or
/// a signature check that did not finish is a gap, which leaves the
/// previous state standing instead of reading as healthy or broken.
public struct VerificationAssessment: Equatable, Sendable {
    public enum IdentityConcern: Equatable, Sendable {
        /// The signing identity differs from the one saved at the last check.
        case changed
        /// It changed at this date and no passing test was recorded since.
        case unverified(since: Date)
    }

    /// A part of the check that could not be read.
    public struct Gap: Equatable, Sendable {
        public let kind: ObservationFailure.Kind
        public let message: String
    }

    private static let detailLimit = 200

    /// Expected permissions macOS reports as denied or limited.
    public private(set) var notGranted: [PermissionService] = []
    public private(set) var identity: IdentityConcern?
    public private(set) var gaps: [Gap] = []

    public var needsVerification: Bool { !notGranted.isEmpty || identity != nil }

    /// Every part was read, so the absence of a concern is a real result.
    public var isComplete: Bool { gaps.isEmpty }

    public init(app: WatchedApp, reading: WatchedAppReading) {
        assessPermissions(expected: app.expectedServices, read: reading.permissions)
        assessIdentity(of: app, current: reading.identity)
    }

    // MARK: - Parts

    private mutating func assessPermissions(expected: [PermissionService],
                                            read: [PermissionService: AuthorizationResult]?) {
        guard !expected.isEmpty else { return }

        guard let read else {
            gaps.append(Gap(kind: .toolMissing,
                            message: "Permission records cannot be read on this Mac (tccutil list is unavailable)."))
            return
        }

        for service in expected {
            guard let result = read[service] else {
                gaps.append(Gap(kind: .failed, message: "\(service.title) was not read."))
                continue
            }
            switch result.state {
            case .granted:
                continue
            case .denied, .limited:
                notGranted.append(service)
            case .unknown, .unavailable:
                gaps.append(Gap(kind: .failed,
                                message: "\(service.title): \(String(result.detail.prefix(Self.detailLimit)))"))
            }
        }
    }

    private mutating func assessIdentity(of app: WatchedApp, current: AppIdentity) {
        if current.hasChanged(from: app.identity) {
            identity = .changed
            return
        }

        if app.identity.signatureValid != nil && current.signatureValid == nil {
            gaps.append(Gap(kind: .failed, message: "The signature check did not finish."))
        }

        // An earlier change the pane recorded stays a concern until the
        // user confirms the app works again with a passing test.
        if let changedAt = app.identityChangedAt,
           !(app.lastKnownWorking.map { $0 >= changedAt } ?? false) {
            identity = .unverified(since: changedAt)
        }
    }
}
