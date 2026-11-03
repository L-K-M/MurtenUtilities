import Foundation
import ShortkingCore

enum SymbolicHotKeyParsing {
    private static let unassignedCharacter = 65535

    static func character(_ value: Int?) -> String? {
        guard let value, value > 0, value != unassignedCharacter,
              let exact = UInt32(exactly: value),
              let scalar = Unicode.Scalar(exact) else { return nil }
        return String(scalar)
    }

    static func merge(plist: Claim?, live: Claim, liveEnabled: Bool?) -> Claim {
        guard var claim = plist else { return live }
        let plistEnabled = claim.enabled
        claim.merge(live)
        claim.combo = live.combo
        // A live read wins; an unavailable enabled flag adds no new information.
        claim.enabled = liveEnabled ?? plistEnabled
        return claim
    }
}
