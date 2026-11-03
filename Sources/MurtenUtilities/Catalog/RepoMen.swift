import MurtenModuleKit
import RepoMenModule

extension ModuleCatalog {
    /// RepoMen's provider (docs/migrating-a-module.md).
    static let repoMen: ModuleFactory? = RepoMenModuleFactory.factory
}
