import MurtenModuleKit
import ZenBackupManagerModule

extension ModuleCatalog {
    /// Zen Backup Manager's provider (docs/modules.md, Zen Backup Manager).
    static let zenBackupManager: ModuleFactory? = ModuleFactory(moduleID: "zenbackupmanager") { _ in
        ZenBackupManagerProvider()
    }
}
