import MurtenModuleKit
import CoreographyModule

extension ModuleCatalog {
    /// Coreography's provider (docs/modules.md, Coreography).
    static let coreography: ModuleFactory? = ModuleFactory(moduleID: "coreography") { context in
        CoreographyProvider(context: context)
    }
}
