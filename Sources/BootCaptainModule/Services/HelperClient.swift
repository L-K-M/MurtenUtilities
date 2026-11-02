import Foundation
import ServiceManagement
import BootCaptainCore
import BootCaptainKit

/// Stands in for BootCaptain's privileged helper, which the suite leaves out.
///
/// The standalone app registers an `SMAppService.daemon` and both sides pin
/// each other's exact bundle ID and Team ID. Murten Utilities is ad-hoc
/// signed, so that connection could never be authenticated
/// (docs/architecture.md, Module packaging). Actions that need the helper —
/// moving `/Library` items to the root vault, and the launchd/cron toggles
/// the standalone build already keeps disabled — stay visible but disabled
/// with `unavailableReason`; everything that runs as the user keeps working.
/// Re-adding the helper means restoring the standalone `HelperClient` and
/// embedding the helper once the suite is signed with a real Team ID.
@MainActor
final class HelperClient: ObservableObject {
    static let unavailableReason = "Needs a signed build of Murten Utilities."

    /// False in every ad-hoc signed build.
    let isAvailable = false

    /// Refuses every request; nothing reaches a privileged process.
    func perform(_ request: ActionRequest) async -> ActionOutcome {
        ActionOutcome(status: .aborted, message: "\(Self.unavailableReason) Nothing was changed.")
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
