import MurtenModuleKit
import BootCaptainModule

extension ModuleCatalog {
    /// BootCaptain's provider (docs/migrating-a-module.md).
    static let bootCaptain: ModuleFactory? = ModuleFactory(moduleID: "bootcaptain") { context in
        BootCaptainProvider(context: context)
    }
}
