import MurtenModuleKit
import ObtainintoshModule

extension ModuleCatalog {
    /// Obtainintosh's provider (docs/modules.md, Obtainintosh).
    static let obtainintosh: ModuleFactory? = ModuleFactory(moduleID: "obtainintosh") { context in
        ObtainintoshProvider(context: context)
    }
}
