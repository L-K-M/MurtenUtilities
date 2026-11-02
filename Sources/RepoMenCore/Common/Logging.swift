import Foundation
import os

/// Namespaced loggers (never log user file *contents*; paths are fine — this is a
/// local utility and paths are the whole point of its logs). Inside the suite the
/// subsystem is the suite's bundle id, so categories carry the module's name.
package enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "ch.lkmc.MurtenUtilities"
    package static let app = Logger(subsystem: subsystem, category: "repomen.app")
    package static let scan = Logger(subsystem: subsystem, category: "repomen.scan")
    package static let reclaim = Logger(subsystem: subsystem, category: "repomen.reclaim")
    package static let watch = Logger(subsystem: subsystem, category: "repomen.watch")
    package static let snapshots = Logger(subsystem: subsystem, category: "repomen.snapshots")
}
