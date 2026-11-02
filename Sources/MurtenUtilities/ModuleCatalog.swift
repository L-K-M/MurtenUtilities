import MurtenModuleKit

/// Every migrated module, registered by id. A module appears on the home
/// screen from `ModuleRegistry` either way; registering it here makes its
/// tile open a pane and lets its watcher run. Each module sets its own
/// factory in `Catalog/<Tool>.swift`.
enum ModuleCatalog {
    static var factories: [ModuleFactory] {
        [dockVac, repoMen, bootCaptain, deviceControlDoctor, shortking,
         hallPass, zenBackupManager, obtainintosh, runningMan, coreography].compactMap { $0 }
    }
}
