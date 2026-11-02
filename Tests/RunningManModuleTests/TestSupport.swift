import Foundation
@testable import RunningManModule

extension AppModel {
    /// The preview workspace never reads or writes preferences, so the moved tests keep
    /// their standalone form; each checks that the standard store stays untouched.
    @MainActor convenience init(demoMode: Bool) {
        self.init(defaults: .standard, demoMode: demoMode)
    }
}
