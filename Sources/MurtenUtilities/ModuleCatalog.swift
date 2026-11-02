import MurtenModuleKit

/// Every migrated module, registered by id. A module appears on the home
/// screen from `ModuleRegistry` either way; registering it here makes its
/// tile open a pane and lets its watcher run.
enum ModuleCatalog {
    static let factories: [ModuleFactory] = []
}
