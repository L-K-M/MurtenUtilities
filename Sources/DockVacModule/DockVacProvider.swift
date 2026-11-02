import DockVacCore
import DockVacDocker
import MurtenCore
import MurtenModuleKit
import SwiftUI

/// DockVac in the suite. The provider lives as long as the app and owns the controller,
/// so a scan, a selection or a running cleanup survives navigating away from the pane.
/// Nothing touches Docker until the pane first opens, apart from the opt-in watcher.
@MainActor
public final class DockVacProvider: SuiteModuleProvider {
  /// How the suite's catalog registers DockVac.
  public nonisolated static func factory() -> ModuleFactory {
    ModuleFactory(moduleID: DockVacSuite.moduleID) { DockVacProvider(context: $0) }
  }

  public let moduleID = DockVacSuite.moduleID
  /// `murten://dockvac/reclaim?endpoint=<address>`: re-scan that endpoint and select what
  /// Docker can rebuild there, for review.
  public let routeActions: [String: Set<String>] = [
    DockVacSuite.reclaimAction: [DockVacSuite.endpointContext]
  ]
  public let watch: WatcherRegistration?

  let controller: AppController
  private let locator: DockerEndpointLocator
  private let context: ModuleContext

  public convenience init(context: ModuleContext) {
    let locator = DockerEndpointLocator()
    let sshPreference = SSHBackgroundPreference(defaults: context.defaults)
    self.init(
      context: context, controller: AppController(), locator: locator,
      reader: LiveDockerUsageReader(
        locator: locator, readTimeout: DockVacWatcher.timeout,
        allowsSSH: { sshPreference.isOn }))
  }

  init(
    context: ModuleContext, controller: AppController, locator: DockerEndpointLocator,
    reader: any DockerUsageReading
  ) {
    self.controller = controller
    self.locator = locator
    self.context = context
    watch = WatcherRegistration(
      watcher: DockVacWatcher(reader: reader), rule: RebuildableSpaceRule())
    // A cleanup changes what the watcher would report; re-check soon so a suggestion the
    // cleanup settled resolves without waiting an hour.
    controller.onCleanupFinished = { context.requestRecheck() }
  }

  /// Applicable when a Docker endpoint can be located without connecting: a socket in a
  /// known place, or DOCKER_HOST or a Docker context naming one.
  public func applicability() async -> Applicability {
    let locator = self.locator
    let locatable = await Task.detached { locator.hasLocatableEndpoint() }.value
    return locatable ? .applicable : .inapplicable(reason: "No Docker endpoint found")
  }

  public func makePane(route: ModuleRoute?) -> AnyView {
    AnyView(DockVacPane(controller: controller, route: route))
  }

  public func makeSettings() -> AnyView? {
    let context = self.context
    return AnyView(DockVacSettings(requestRecheck: { context.requestRecheck() }))
  }

  /// Replaces the standalone app's quit alert.
  public var interruptionWarning: String? {
    guard controller.isCleaning else { return nil }
    return
      "A cleanup is still running. Docker finishes the operation in progress either way, but DockVac cannot show you its result."
  }
}
