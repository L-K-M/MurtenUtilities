import Foundation
import ObtainintoshCore

/// The one download allowed at a time. A second one, for any program, is
/// refused rather than racing the first: the pane has a single progress
/// panel, and two downloads would interleave in it.
public final class DownloadSlot: @unchecked Sendable {
    /// Holds the slot until released or deallocated, which covers every
    /// early exit too.
    public final class Lease: @unchecked Sendable {
        private let slot: DownloadSlot
        private var released = false
        private let lock = NSLock()

        fileprivate init(slot: DownloadSlot) {
            self.slot = slot
        }

        public func release() {
            let first = lock.withLock { () -> Bool in
                defer { released = true }
                return !released
            }
            if first { slot.free() }
        }

        deinit {
            release()
        }
    }

    private let lock = NSLock()
    /// What is running, for the refusal message. Guarded by `lock`.
    private var active: String?

    public init() {}

    /// Claims the slot for `operation`, e.g. "Tool (id)".
    public func acquire(_ operation: String) throws -> Lease {
        try lock.withLock {
            if let active {
                throw ObtainintoshError("A download for \(active) is already in progress; wait for it to finish "
                    + "before starting another")
            }
            active = operation
        }
        return Lease(slot: self)
    }

    public var activeOperation: String? {
        lock.withLock { active }
    }

    fileprivate func free() {
        lock.withLock { active = nil }
    }
}
