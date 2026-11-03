import Foundation

struct MenuWalkBudget {
    enum Incomplete: Error { case unavailable, interrupted }

    // Per-read and per-app limits keep unresponsive or hostile menus bounded.
    static let messagingTimeout: TimeInterval = 0.25
    static let appDuration: TimeInterval = 2
    static let maximumDepth = 6
    private static let maxItems = 4_000

    private let deadline: Date
    private var remaining = maxItems
    private(set) var wasTruncated = false

    init(startedAt: Date = Date()) {
        deadline = startedAt.addingTimeInterval(Self.appDuration)
    }

    func readTimeout(now: Date = Date()) throws -> Float {
        guard !Task.isCancelled, now < deadline else { throw Incomplete.interrupted }
        return Float(min(Self.messagingTimeout, deadline.timeIntervalSince(now)))
    }

    mutating func visit(depth: Int) throws -> Bool {
        _ = try readTimeout()
        guard depth <= Self.maximumDepth else {
            wasTruncated = true
            return false
        }
        guard remaining > 0 else { throw Incomplete.interrupted }
        remaining -= 1
        return true
    }
}
