import DockVacCore
import DockVacDocker
import Foundation
import MurtenCore

/// All DockVac's watcher may do with Docker: find the daemon the automatic search finds
/// and read what the safe cleanup level is computed from. There is no removal here, and
/// the live reader never hands out its Engine client, so a poll cannot delete anything by
/// mistake. That is a guardrail, not a sandbox: the same socket would accept a removal.
protocol DockerUsageReading: Sendable {
  /// Whether reading talks to another machine: DOCKER_HOST or the active Docker context
  /// names an SSH host.
  var readsRemoteEndpoint: Bool { get }
  /// Reads containers, images and build cache from the endpoint the automatic search
  /// finds. Throws `DockerUsageReadFailure` once an endpoint answered, so the failure
  /// names its scope; throws the locator's error when none did.
  func readUsage() async throws -> DockerUsageSnapshot
}

struct DockerUsageSnapshot: Sendable {
  /// `DockerEndpoint.address`: a socket path or an `ssh://` address.
  let endpointAddress: String
  let usage: DockerDiskUsage
}

/// A read that reached an endpoint and then failed.
struct DockerUsageReadFailure: Error {
  let endpointAddress: String
  let underlying: any Error
}

/// The live reader: the locator's automatic search, then the Engine API reads the safe
/// level needs. SSH runs with BatchMode, so a host needing a password or passphrase fails
/// instead of prompting.
struct LiveDockerUsageReader: DockerUsageReading {
  let locator: DockerEndpointLocator
  /// Longest silence tolerated from the daemon; the suite's timeout cancels sooner.
  let readTimeout: TimeInterval

  var readsRemoteEndpoint: Bool {
    if case .ssh? = locator.configuredHost()?.host {
      return true
    }
    return false
  }

  func readUsage() async throws -> DockerUsageSnapshot {
    let connection = try await locator.connect(to: .automatic)
    let address = connection.endpoint.address
    let client = DockerEngineClient(endpoint: connection.endpoint, idleTimeout: readTimeout)
    do {
      var usage = DockerDiskUsage()
      usage.containers = try await client.listContainers()
      let images = try await client.imageUsage()
      usage.images = images.images
      usage.layersSizeBytes = images.layersSizeBytes
      // Volumes are skipped: no cleanup level removes one, and sizing them walks every
      // volume's files, the slowest read of a scan.
      usage.buildCache = try await client.buildCacheUsage()
      return DockerUsageSnapshot(endpointAddress: address, usage: usage)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw DockerUsageReadFailure(endpointAddress: address, underlying: error)
    }
  }
}

/// Hourly: how much space Docker could rebuild on the endpoint DockVac finds by itself.
/// One finding per poll, scoped by endpoint address, whose evidence is the safe level's
/// plan, so the headline matches what the pane then selects.
struct DockVacWatcher: Watcher {
  static let interval: TimeInterval = 60 * 60
  /// Disk-usage reads on a large install can take minutes; give them three before the
  /// poll counts as timed out.
  static let timeout: TimeInterval = 3 * 60

  let moduleID = DockVacSuite.moduleID
  let reader: any DockerUsageReading
  let now: @Sendable () -> Date

  init(reader: any DockerUsageReading, now: @escaping @Sendable () -> Date = { Date() }) {
    self.reader = reader
    self.now = now
  }

  /// Re-read on every poll, so switching to a remote context pauses the check on metered
  /// networks from the next poll on.
  var cadence: WatchCadence {
    WatchCadence(
      interval: Self.interval, timeout: Self.timeout,
      resources: reader.readsRemoteEndpoint ? .network : [])
  }

  func observe() async -> WatchObservation {
    do {
      let snapshot = try await reader.readUsage()
      let date = now()
      let report = UsageAnalyzer.analyze(snapshot.usage, capturedAt: date)
      let finding = DockVacSuite.reclaimableFinding(
        endpoint: snapshot.endpointAddress, plan: report.automaticCleanupPlan(.safe), at: date)
      return .complete(moduleID: moduleID, at: date, scopes: [finding.scope], findings: [finding])
    } catch let failure as DockerUsageReadFailure {
      return WatchObservation(
        moduleID: moduleID, observedAt: now(), findings: [], completedScopes: [],
        failures: [Self.failure(failure.underlying, scope: FindingScope(failure.endpointAddress))])
    } catch {
      return .unavailable(moduleID: moduleID, at: now(), Self.failure(error, scope: nil))
    }
  }

  /// A short diagnostic for the suite: the first line of DockVac's own message.
  static func failure(_ error: any Error, scope: FindingScope?) -> ObservationFailure {
    if error is CancellationError {
      return ObservationFailure(kind: .failed, scope: scope, message: "The check was cancelled.")
    }
    let message =
      dockerErrorMessage(error).split(separator: "\n").first.map(String.init)
      ?? "Docker could not be read."
    guard let engineError = error as? DockerEngineError else {
      return ObservationFailure(kind: .failed, scope: scope, message: message)
    }

    let kind: ObservationFailure.Kind
    switch engineError {
    case .daemonNotFound:
      kind = .unreachable
    case .socketUnavailable(_, let detail), .sshUnavailable(_, let detail):
      // A refused key or socket permission is a credential problem the watcher may not
      // fix by prompting; the user connects from the pane instead.
      kind = detail.localizedCaseInsensitiveContains("permission denied") ? .permissionDenied : .unreachable
    case .timedOut:
      kind = .timedOut
    case .malformedResponse, .decoding:
      kind = .malformedResponse
    case .api:
      kind = .failed
    }
    return ObservationFailure(kind: kind, scope: scope, message: message)
  }
}
