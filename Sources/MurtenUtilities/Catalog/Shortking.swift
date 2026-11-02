import MurtenModuleKit
import ShortkingModule

extension ModuleCatalog {
    /// Shortking's provider (docs/modules.md, Shortking).
    static let shortking: ModuleFactory? = ModuleFactory(moduleID: ShortkingProvider.identifier) { context in
        ShortkingProvider(context: context)
    }
}
