import AppKit
import SwiftUI
import MurtenCore

/// The home window's content: the tool grid, or one module's pane with a
/// way back. One window, one pane at a time (PLAN.md, Product shape).
public struct RootView: View {
    @Bindable private var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if let route = model.openRoute, let module = model.module(route.moduleID) {
                PaneContainer(model: model, module: module, route: route)
                    .navigationTitle(module.name)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                model.openHome()
                            } label: {
                                Label("All Tools", systemImage: "square.grid.2x2")
                            }
                            .keyboardShortcut("[", modifiers: .command)
                            .help("Back to all tools (⌘[)")
                        }
                    }
            } else {
                HomeView(model: model)
                    .navigationTitle("Murten Utilities")
            }
        }
        .frame(minWidth: 880, minHeight: 600)
        .background(WindowFronting(requests: model.windowRequests))
        .task { await model.start() }
    }
}

/// Brings the hosting window forward whenever the model asks, e.g. after a
/// suggestion was opened from the menu bar.
private struct WindowFronting: NSViewRepresentable {
    let requests: Int

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard requests != context.coordinator.handled else { return }
        context.coordinator.handled = requests
        guard requests > 0 else { return }
        NSApp.activate()
        nsView.window?.makeKeyAndOrderFront(nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var handled = 0
    }
}

/// Hosts one module's pane with the module's own preferences store.
struct PaneContainer: View {
    let model: AppModel
    let module: SuiteModule
    let route: ModuleRoute

    var body: some View {
        if let pane = model.pane(for: route) {
            pane
                // A new route (another suggestion for the same module)
                // rebuilds the pane so it re-reads its preselection.
                .id(route)
                .defaultAppStorage(model.defaults(for: module.id))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(module.name, systemImage: module.systemImage,
                                   description: Text("This tool is not available yet."))
        }
    }
}
