import DockVacCore
import Foundation
import XCTest

@testable import DockVacDocker

/// The suite asks whether Docker can be found before it shows DockVac or runs its watcher.
/// That answer must come from configuration and file metadata alone, never a connection.
final class DockerEndpointLocatorTests: XCTestCase {
  private var home: URL!

  override func setUpWithError() throws {
    home = FileManager.default.temporaryDirectory
      .appendingPathComponent("dockvac-locator-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: home)
  }

  private func locator(_ environment: [String: String] = [:]) -> DockerEndpointLocator {
    DockerEndpointLocator(environment: environment, homeDirectory: home.path, probeTimeout: 1)
  }

  private func write(_ text: String, to relativePath: String) throws {
    let url = home.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
  }

  func testNothingConfiguredAndNoSocketIsNotLocatable() throws {
    try XCTSkipIf(
      FileManager.default.fileExists(atPath: "/var/run/docker.sock"),
      "this machine has a system Docker socket")
    XCTAssertNil(locator().configuredHost())
    XCTAssertFalse(locator().hasLocatableEndpoint())
  }

  func testAnExistingCandidateSocketIsLocatable() throws {
    try write("", to: ".docker/run/docker.sock")
    XCTAssertTrue(locator().hasLocatableEndpoint())
  }

  func testDockerHostIsLocatableWithoutASocket() throws {
    let local = locator(["DOCKER_HOST": "unix:///nowhere/docker.sock"])
    XCTAssertTrue(local.hasLocatableEndpoint())
    XCTAssertEqual(local.configuredHost()?.host, .unixSocket(path: "/nowhere/docker.sock"))

    let remote = locator(["DOCKER_HOST": "ssh://deploy@build-box"])
    XCTAssertTrue(remote.hasLocatableEndpoint())
    guard case .ssh(let host)? = remote.configuredHost()?.host else {
      return XCTFail("an ssh:// DOCKER_HOST is a remote endpoint")
    }
    XCTAssertEqual(host.host, "build-box")
  }

  func testActiveContextIsLocatable() throws {
    try write(#"{"currentContext": "remote"}"#, to: ".docker/config.json")
    try write(
      #"{"Name": "remote", "Endpoints": {"docker": {"Host": "ssh://build-box"}}}"#,
      to: ".docker/contexts/meta/0123abcd/meta.json")
    let configured = try XCTUnwrap(locator().configuredHost())
    XCTAssertEqual(configured.origin, "Docker context remote")
    guard case .ssh = configured.host else {
      return XCTFail("the context names an SSH host")
    }
    XCTAssertTrue(locator().hasLocatableEndpoint())
  }
}
