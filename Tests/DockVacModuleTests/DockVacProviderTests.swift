import AppKit
import DockVacCore
import DockVacDocker
import MurtenCore
import MurtenModuleKit
import SwiftUI
import XCTest

@testable import DockVacModule

/// The provider and the pane's controller against a fake daemon: what a suggestion's
/// route selects, and what it never does.
final class DockVacProviderTests: XCTestCase {
  private static let socket = "/Users/test/.docker/run/docker.sock"

  // MARK: - Routes

  @MainActor
  func testReclaimRouteSelectsExactlyTheSafeLevelOfThatEndpoint() async throws {
    let controller = AppController(service: Self.service(reaching: Self.socket))
    controller.open(DockVacSuite.reclaimRoute(endpoint: Self.socket))
    try await waitForReport(controller)

    let report = UsageAnalyzer.analyze(try ModuleFixtures.diskUsage())
    XCTAssertEqual(controller.basket, Set(report.automaticCleanupIDs(.safe)))
    XCTAssertFalse(controller.basket.isEmpty)
    for id in controller.basket {
      XCTAssertTrue(
        id.kind == .images || id.kind == .buildCache, "never a container or volume: \(id)")
      if id.kind == .images {
        let image = try XCTUnwrap(report.usage.images.first { $0.id == id.rawValue })
        XCTAssertTrue(image.isDangling, "never a re-pullable or local tagged image: \(image.id)")
      }
    }
    XCTAssertFalse(controller.isSheetPresented, "opening a suggestion never asks to remove")
    XCTAssertFalse(controller.isCleaning)
    XCTAssertTrue(controller.chrome.state.canReview, "one click away from the confirmation")
    XCTAssertEqual(controller.notice?.hasPrefix("Selected what Docker can rebuild"), true)
  }

  @MainActor
  func testReclaimRouteForAnotherEndpointSelectsNothing() async throws {
    let controller = AppController(service: Self.service(reaching: "/somewhere/else.sock"))
    controller.open(DockVacSuite.reclaimRoute(endpoint: Self.socket))
    try await waitForReport(controller)

    XCTAssertTrue(controller.basket.isEmpty, "a selection is bound to the endpoint it was counted on")
    XCTAssertEqual(controller.notice?.contains("Nothing was selected"), true)
  }

  @MainActor
  func testReclaimRouteForAnSSHEndpointConnectsToThatHost() async throws {
    let targets = Recorder<DockerConnectionTarget>()
    let address = "ssh://deploy@build-box:2222"
    let controller = AppController(service: Self.service(reaching: address, targets: targets))
    controller.open(DockVacSuite.reclaimRoute(endpoint: address))
    try await waitForReport(controller)

    XCTAssertEqual(targets.values, [.ssh(try DockerSSHHost(address))])
    XCTAssertFalse(controller.basket.isEmpty)
  }

  @MainActor
  func testReclaimRouteReplacesAnEarlierSelection() async throws {
    let controller = AppController(service: Self.service(reaching: Self.socket))
    controller.open(nil)
    try await waitForReport(controller)
    let volume = try XCTUnwrap(
      controller.report.items.first { $0.id.kind == .localVolumes && !$0.removability.isBlocked },
      "the fixtures hold a removable volume")
    controller.addToBasket([volume.id])
    XCTAssertTrue(controller.basket.contains(volume.id))

    controller.open(DockVacSuite.reclaimRoute(endpoint: Self.socket))
    try await waitForReport(controller)
    XCTAssertFalse(controller.basket.contains(volume.id), "a volume is never preselected")
    XCTAssertEqual(controller.basket, Set(controller.report.automaticCleanupIDs(.safe)))
  }

  @MainActor
  func testFirstOpenScansOnceAndTileOpensKeepTheReport() async throws {
    let targets = Recorder<DockerConnectionTarget>()
    let controller = AppController(service: Self.service(reaching: Self.socket, targets: targets))
    XCTAssertEqual(controller.phase, .idle, "nothing is scanned before the pane opens")
    XCTAssertTrue(targets.values.isEmpty)

    controller.open(nil)
    try await waitForReport(controller)
    controller.open(ModuleRoute(moduleID: DockVacSuite.moduleID))
    try await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertEqual(targets.values.count, 1)
    XCTAssertEqual(controller.phase, .report)
    XCTAssertNil(controller.notice)
  }

  // MARK: - Provider

  @MainActor
  func testProviderDeclaresTheReclaimRouteAndAnHourlyWatcher() throws {
    let provider = makeProvider()
    XCTAssertEqual(provider.moduleID, DockVacSuite.moduleID)
    XCTAssertEqual(provider.routeActions, ["reclaim": ["endpoint"]])
    let watch = try XCTUnwrap(provider.watch)
    XCTAssertEqual(watch.moduleID, DockVacSuite.moduleID)
    XCTAssertEqual(watch.watcher.cadence.interval, 3600)
    XCTAssertTrue(watch.rule is RebuildableSpaceRule)
  }

  @MainActor
  func testSettingsOfferTheSSHChoice() throws {
    let settings = try XCTUnwrap(makeProvider().makeSettings())
    let host = NSHostingView(rootView: settings)
    host.frame = NSRect(x: 0, y: 0, width: 460, height: 220)
    host.layoutSubtreeIfNeeded()
    XCTAssertEqual(SSHBackgroundPreference.key, "checkSSHEndpointsInBackground")
  }

  @MainActor
  func testQuitWarningOnlyWhileCleaningAndARecheckAfterwards() async throws {
    let rechecks = Recorder<Void>()
    let service = Self.service(reaching: Self.socket)
    let controller = AppController(service: service)
    let provider = makeProvider(controller: controller, requestRecheck: { rechecks.append(()) })
    XCTAssertNil(provider.interruptionWarning)

    controller.open(nil)
    try await waitForReport(controller)
    service.runCleanup(.empty)
    XCTAssertEqual(provider.interruptionWarning?.hasPrefix("A cleanup is still running."), true)

    let deadline = Date().addingTimeInterval(5)
    while controller.isCleaning, Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
    XCTAssertNil(provider.interruptionWarning)
    XCTAssertEqual(rechecks.values.count, 1, "the suite re-checks Docker after a cleanup")
  }

  @MainActor
  func testApplicableOnlyWhenAnEndpointCanBeLocated() async throws {
    let home = NSTemporaryDirectory() + "dockvac-provider-\(UUID().uuidString)"
    let configured = makeProvider(
      locator: DockerEndpointLocator(environment: ["DOCKER_HOST": "ssh://build-box"], homeDirectory: home))
    let applicable = await configured.applicability()
    XCTAssertEqual(applicable, .applicable)

    try XCTSkipIf(
      FileManager.default.fileExists(atPath: "/var/run/docker.sock"),
      "this machine has a system Docker socket")
    let bare = makeProvider(locator: DockerEndpointLocator(environment: [:], homeDirectory: home))
    let inapplicable = await bare.applicability()
    XCTAssertEqual(inapplicable, .inapplicable(reason: "No Docker endpoint found"))
  }

  @MainActor
  func testPaneRendersHostedAndScansOnlyOnceShown() async throws {
    let targets = Recorder<DockerConnectionTarget>()
    let controller = AppController(service: Self.service(reaching: Self.socket, targets: targets))
    let provider = makeProvider(controller: controller)

    let host = NSHostingView(rootView: provider.makePane(route: nil))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680), styleMask: [.titled, .resizable],
      backing: .buffered, defer: true)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    let deadline = Date().addingTimeInterval(5)
    while controller.phase != .report, Date() < deadline {
      try await Task.sleep(nanoseconds: 10_000_000)
      host.layoutSubtreeIfNeeded()
    }
    XCTAssertNotNil(controller.pane, "the hosted pane attaches to the provider's controller")
    XCTAssertEqual(controller.phase, .report, "the first appearance scans")
    XCTAssertEqual(targets.values.count, 1)
    window.contentView = nil
  }

  // MARK: - Helpers

  @MainActor
  private func makeProvider(
    controller: AppController = AppController(
      service: DockVacProviderTests.service(reaching: DockVacProviderTests.socket)),
    locator: DockerEndpointLocator = DockerEndpointLocator(environment: [:], homeDirectory: "/nonexistent"),
    requestRecheck: @escaping @MainActor () -> Void = {}
  ) -> DockVacProvider {
    let defaults = UserDefaults(suiteName: "DockVacModuleTests.\(UUID().uuidString)")!
    let context = ModuleContext(
      moduleID: DockVacSuite.moduleID, defaults: defaults, requestRecheck: requestRecheck,
      open: { _ in })
    return DockVacProvider(
      context: context, controller: controller, locator: locator, reader: NoDockerReader())
  }

  /// A service whose daemon answers at `address` with the captured fixtures.
  @MainActor
  private static func service(
    reaching address: String, targets: Recorder<DockerConnectionTarget>? = nil
  ) -> DockerService {
    DockerService(
      connect: { target in
        targets?.append(target)
        let endpoint =
          address.hasPrefix("ssh://")
          ? DockerEndpoint(sshHost: try DockerSSHHost(address))
          : DockerEndpoint(socketPath: address, origin: "Docker Desktop")
        return DockerConnection(
          endpoint: endpoint,
          version: DockerEngineVersion(
            version: "29.3.1", apiVersion: "1.54", minimumAPIVersion: nil, os: "linux",
            arch: "arm64", platformName: nil),
          ping: DockerPing(apiVersion: "1.54", builderVersion: nil, osType: "linux"))
      },
      readUsage: { _, _ in try ModuleFixtures.diskUsage() })
  }

  /// Waits for the scan the last action started to finish.
  @MainActor
  private func waitForReport(_ controller: AppController) async throws {
    let deadline = Date().addingTimeInterval(5)
    while controller.phase != .report, Date() < deadline {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertEqual(controller.phase, .report)
  }
}

private struct NoDockerReader: DockerUsageReading {
  let readsRemoteEndpoint = false

  func readUsage() async throws -> DockerUsageSnapshot {
    throw DockerEngineError.daemonNotFound(attempts: [], unsupported: [])
  }
}

/// Collects values from closures the fake daemon calls off the main actor.
private final class Recorder<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [Value] = []

  func append(_ value: Value) {
    lock.withLock { recorded.append(value) }
  }

  var values: [Value] {
    lock.withLock { recorded }
  }
}
