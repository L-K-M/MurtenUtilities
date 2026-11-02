import Foundation

/// The background check's GitHub allowance: at most `maximumRequests` per
/// poll, and never the last `keepInReserve` of the hourly limit GitHub
/// reports, so a poll cannot use up what the user's own checks need.
/// Unauthenticated, GitHub allows 60 requests an hour.
public actor GitHubRateBudget: RequestBudget {
    public static let unauthenticatedAllowance = 20
    public static let authenticatedAllowance = 300

    private let maximumRequests: Int
    private let keepInReserve: Int
    private var spent = 0
    private var remaining: Int?

    public init(maximumRequests: Int, keepInReserve: Int = 10) {
        self.maximumRequests = maximumRequests
        self.keepInReserve = keepInReserve
    }

    public func spend() throws {
        let exhausted = spent >= maximumRequests || (remaining.map { $0 <= keepInReserve } ?? false)
        guard !exhausted else {
            throw LookupFailure(.rateLimited, "Not checked, to stay within GitHub's hourly request limit; "
                + "it is checked again next time.")
        }
        spent += 1
    }

    public func record(headers: [String: String]) {
        if let value = headers["x-ratelimit-remaining"].flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) {
            remaining = value
        }
    }
}
