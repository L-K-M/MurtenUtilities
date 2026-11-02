import AppKit
import MurtenCore
import MurtenModuleKit
import SwiftUI

/// DockVac's pane in the suite window: the AppKit report, hosted, plus its commands in
/// the suite's Tool menu. The suite rebuilds this view on every navigation; the
/// controller, and with it the scan and the selection, belongs to the provider.
struct DockVacPane: View {
  let controller: AppController
  let route: ModuleRoute?
  @State private var opened = false

  var body: some View {
    PaneHost(controller: controller)
      .moduleCommands(DockVacCommands.make(for: controller, state: controller.chrome.state))
      .onAppear {
        // Once per pane: a route is acted on when it opens the pane, not when the
        // window reappears.
        guard !opened else { return }
        opened = true
        controller.open(route)
      }
  }
}

/// Attaches a fresh `PaneViewController` to the long-lived controller.
private struct PaneHost: NSViewControllerRepresentable {
  let controller: AppController

  func makeNSViewController(context: Context) -> PaneViewController {
    let pane = PaneViewController()
    controller.attach(pane)
    return pane
  }

  func updateNSViewController(_ pane: PaneViewController, context: Context) {}

  static func dismantleNSViewController(_ pane: PaneViewController, coordinator: ()) {
    pane.controller?.detach(pane)
  }
}
