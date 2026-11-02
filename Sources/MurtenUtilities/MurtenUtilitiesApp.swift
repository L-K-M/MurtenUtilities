import SwiftUI
import MurtenShell

@main
struct MurtenUtilitiesApp: App {
    @NSApplicationDelegateAdaptor(SuiteAppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        let model = AppModel(factories: ModuleCatalog.factories, services: .live())
        _model = State(initialValue: model)
        SuiteAppDelegate.model = model
    }

    var body: some Scene {
        SuiteScenes(model: model)
    }
}
