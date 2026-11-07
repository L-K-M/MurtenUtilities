import Foundation

/// Distinguishes a running process from a later reuse of its PID, even when
/// the replacement runs the same executable.
struct ProcessStartTime: Hashable, Sendable {
    let seconds: Int64
    let microseconds: Int64
}
