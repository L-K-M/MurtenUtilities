import MurtenModuleKit
import RunningManModule

extension ModuleCatalog {
    /// RunningMan's provider (docs/modules.md, RunningMan).
    static let runningMan: ModuleFactory? = ModuleFactory(moduleID: "runningman") { RunningManProvider(context: $0) }
}
