import MurtenModuleKit
import HallPassModule

extension ModuleCatalog {
    /// HallPass's provider: an on-demand pane without a watcher
    /// (docs/modules.md, HallPass).
    static let hallPass: ModuleFactory? = ModuleFactory(moduleID: HallPassProvider.identifier) { context in
        HallPassProvider(context: context)
    }
}
