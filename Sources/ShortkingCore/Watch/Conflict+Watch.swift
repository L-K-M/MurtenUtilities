import Foundation

// MARK: - What the suite watches for

public extension Conflict {

    /// Two or more parties fighting over one shortcut, as the Overview's "Two apps
    /// want the same shortcut" section shows them.
    ///
    /// Includes `.shadowed` as well as `.definite`: from the user's side, "macOS
    /// takes ⌃⌘S and Karabiner never gets it" is two apps fighting, whatever the
    /// analyzer calls the shape of it. `.contextual` is left out because it reads
    /// as "works everywhere except here", and macOS's own colliding defaults are
    /// left out because they are Apple's arrangement, not something an installed
    /// app did.
    var isBetweenApps: Bool {
        !isSystemDefault && (kind == .definite || kind == .shadowed)
    }

    /// The claims that are actually fighting.
    ///
    /// Only the global ones when there are any: app menu equivalents come and go
    /// with whichever apps were running during the scan, and an acknowledgement
    /// must not lapse because Safari happened to be closed. A conflict between
    /// menu items of one app has no global claim, so all of them count.
    var contenders: [Claim] {
        let all = [winner].compactMap { $0 } + losers
        let global = all.filter { $0.layer.isGlobal }
        return global.isEmpty ? all : global
    }

    /// Distinct owner names of the contenders, in the analyzer's order.
    var contenderNames: [String] {
        var seen = Set<String>()
        return contenders.map(\.ownerName).filter { seen.insert($0).inserted }
    }

    /// Identifies what the user acknowledged: this shortcut, fought over by these
    /// owners. Another owner joining the fight changes it, so the suite speaks up
    /// again; a rescan that finds the same fight does not.
    ///
    /// `"k49|m9#com.apple.symbolichotkeys,com.raycast.macos"`
    var acknowledgementSignature: String {
        let owners = Set(contenders.map { $0.owner?.identity ?? "unattributed" })
        return combo.groupingKey + "#" + owners.sorted().joined(separator: ",")
    }
}
