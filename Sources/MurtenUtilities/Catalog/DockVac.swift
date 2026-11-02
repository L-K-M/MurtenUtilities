import DockVacModule
import MurtenModuleKit

extension ModuleCatalog {
    /// DockVac's provider (docs/migrating-a-module.md).
    static let dockVac: ModuleFactory? = DockVacProvider.factory()
}
