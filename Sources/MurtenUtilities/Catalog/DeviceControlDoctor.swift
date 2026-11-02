import MurtenModuleKit
import DeviceControlDoctorModule

extension ModuleCatalog {
    /// DeviceControlDoctor's provider (docs/modules.md).
    static let deviceControlDoctor: ModuleFactory? = DeviceControlDoctorProvider.factory
}
