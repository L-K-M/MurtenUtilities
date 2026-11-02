import Foundation
import MurtenCore
import XCTest

@testable import DockVacCore

/// The suite's suggestion for DockVac: what the watcher's finding counts, and when the
/// rule speaks up.
final class RebuildableSpaceRuleTests: XCTestCase {
  private let endpoint = "/var/run/docker.sock"
  private let rule = RebuildableSpaceRule()
  private let observedAt = Date(timeIntervalSince1970: 1_800_000_000)

  private func finding(_ bytes: Int64, condition: String = DockVacSuite.reclaimableCondition)
    -> Finding
  {
    Finding(
      moduleID: DockVacSuite.moduleID, condition: condition, scope: FindingScope(endpoint),
      observedAt: observedAt, evidence: [DockVacSuite.bytesEvidence: .bytes(bytes)])
  }

  // MARK: - Thresholds

  func testOpensAtFourGigabytes() {
    XCTAssertNil(rule.suggestion(for: finding(3_999_999_999), state: .inactive))
    XCTAssertNotNil(rule.suggestion(for: finding(4_000_000_000), state: .inactive))
  }

  func testStaysActiveUntilBelowThreeGigabytes() {
    XCTAssertNotNil(
      rule.suggestion(for: finding(3_500_000_000), state: .active),
      "between the thresholds an active suggestion holds")
    XCTAssertNotNil(rule.suggestion(for: finding(3_000_000_000), state: .active))
    XCTAssertNil(rule.suggestion(for: finding(2_999_999_999), state: .active))
    XCTAssertNil(
      rule.suggestion(for: finding(3_500_000_000), state: .inactive),
      "but does not open one")
  }

  func testIgnoresOtherConditionsAndMissingEvidence() {
    XCTAssertNil(rule.suggestion(for: finding(9_000_000_000, condition: "other"), state: .inactive))
    let bare = Finding(
      moduleID: DockVacSuite.moduleID, condition: DockVacSuite.reclaimableCondition,
      scope: FindingScope(endpoint), observedAt: observedAt)
    XCTAssertNil(rule.suggestion(for: bare, state: .inactive))
  }

  // MARK: - Content

  func testHeadlineRoundsToWholeGigabytes() throws {
    let content = try XCTUnwrap(rule.suggestion(for: finding(8_200_000_000), state: .inactive))
    XCTAssertEqual(content.title, "Docker is holding ~8 GB you can rebuild")
    let low = try XCTUnwrap(rule.suggestion(for: finding(3_100_000_000), state: .active))
    XCTAssertEqual(low.title, "Docker is holding ~3 GB you can rebuild")
  }

  func testRouteReclaimsTheFindingsEndpoint() throws {
    let content = try XCTUnwrap(rule.suggestion(for: finding(5_000_000_000), state: .inactive))
    XCTAssertEqual(content.route.moduleID, DockVacSuite.moduleID)
    XCTAssertEqual(content.route.action, DockVacSuite.reclaimAction)
    XCTAssertEqual(content.route.context, [DockVacSuite.endpointContext: endpoint])
    XCTAssertTrue(content.detail.contains(endpoint))
  }

  func testRouteSurvivesTheSuitesAllowlist() throws {
    let ssh = Finding(
      moduleID: DockVacSuite.moduleID, condition: DockVacSuite.reclaimableCondition,
      scope: FindingScope("ssh://deploy@build-box:2222"), observedAt: observedAt,
      evidence: [DockVacSuite.bytesEvidence: .bytes(6_000_000_000)])
    let route = try XCTUnwrap(rule.suggestion(for: ssh, state: .inactive)).route
    let allowlist = RouteAllowlist(
      modules: [DockVacSuite.moduleID],
      actions: [DockVacSuite.moduleID: [DockVacSuite.reclaimAction: [DockVacSuite.endpointContext]]])
    XCTAssertEqual(try allowlist.route(from: route.url), route)
  }

  // MARK: - What the finding counts

  func testFindingCountsExactlyTheSafeLevelsPlan() throws {
    let report = try Fixtures.report()
    let plan = report.automaticCleanupPlan(.safe)
    let finding = DockVacSuite.reclaimableFinding(endpoint: endpoint, plan: plan, at: observedAt)

    XCTAssertEqual(finding.key.scope, FindingScope(endpoint))
    XCTAssertEqual(finding.bytes(DockVacSuite.bytesEvidence), Int64(plan.estimatedReclaimableBytes))
    XCTAssertEqual(finding.count(DockVacSuite.itemsEvidence), 6)
    XCTAssertEqual(
      Set(plan.operations.map(\.id)), Set(report.automaticCleanupIDs(.safe)),
      "the plan drops nothing the safe level picked")
    XCTAssertGreaterThan(plan.estimatedReclaimableBytes, 0)
    XCTAssertLessThan(
      plan.estimatedReclaimableBytes, report.totalReclaimableBytes,
      "less than everything removable: containers, volumes and tagged images stay out")
  }

  func testFindingNeverCountsContainersVolumesOrTaggedImages() throws {
    let report = try Fixtures.report()
    for operation in report.automaticCleanupPlan(.safe).operations {
      switch operation.id.kind {
      case .containers, .localVolumes:
        XCTFail("the safe level never removes \(operation.id.rawValue)")
      case .images:
        let image = try XCTUnwrap(report.usage.images.first { $0.id == operation.id.rawValue })
        XCTAssertTrue(image.isDangling, "only untagged leftovers: \(image.id)")
      case .buildCache:
        break
      }
    }
  }

  func testVolumesDoNotChangeTheSafePlan() throws {
    // The watcher skips the volume stage, the slowest read; that must not change the count.
    var usage = try Fixtures.diskUsage()
    let full = UsageAnalyzer.analyze(usage, capturedAt: observedAt).automaticCleanupPlan(.safe)
    usage.volumes = []
    let withoutVolumes = UsageAnalyzer.analyze(usage, capturedAt: observedAt)
      .automaticCleanupPlan(.safe)
    XCTAssertEqual(withoutVolumes, full)
  }
}
