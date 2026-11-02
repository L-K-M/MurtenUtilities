import Foundation
import MurtenCore

/// DockVac's vocabulary in the suite: its module id, the condition its watcher reports,
/// and the route a suggestion opens. The rule, the watcher and the pane share these.
public enum DockVacSuite {
  public static let moduleID = "dockvac"
  /// Space the safe automatic cleanup level would free on one Docker endpoint.
  public static let reclaimableCondition = "reclaimable"
  /// Bytes the safe level frees, estimated exactly as the confirmation sheet estimates them.
  public static let bytesEvidence = "bytes"
  /// How many resources the safe level would remove.
  public static let itemsEvidence = "items"
  /// Opens the pane, re-scans the endpoint and selects the safe level for review.
  public static let reclaimAction = "reclaim"
  /// The endpoint address a reclaim route names, as `DockerEndpoint.address` reports it.
  public static let endpointContext = "endpoint"

  public static func reclaimRoute(endpoint: String) -> ModuleRoute {
    ModuleRoute(moduleID: moduleID, action: reclaimAction, context: [endpointContext: endpoint])
  }

  /// One endpoint's rebuildable space. `plan` is the safe level's plan for that endpoint's
  /// report, so the evidence is what preselecting it frees, not `docker system df`'s
  /// RECLAIMABLE column, which also counts stopped containers, volumes and tagged images.
  public static func reclaimableFinding(endpoint: String, plan: CleanupPlan, at date: Date)
    -> Finding
  {
    Finding(
      moduleID: moduleID, condition: reclaimableCondition, scope: FindingScope(endpoint),
      observedAt: date,
      evidence: [
        bytesEvidence: .bytes(Int64(clamping: plan.estimatedReclaimableBytes)),
        itemsEvidence: .count(plan.operations.count),
      ])
  }
}

extension UsageReport {
  /// The plan an automatic cleanup at `level` would confirm: what the pane selects when a
  /// suggestion opens it, and what the watcher reports.
  public func automaticCleanupPlan(_ level: AutomaticCleanupLevel) -> CleanupPlan {
    CleanupPlan.make(selecting: automaticCleanupIDs(level), from: self)
  }
}

/// Suggests a cleanup once an endpoint holds at least 4 GB that Docker can rebuild, and
/// keeps the suggestion until it falls below 3 GB, so a value hovering at the threshold
/// does not open and close episodes.
public struct RebuildableSpaceRule: SuggestionRule {
  /// Decimal gigabytes, the unit Docker and `ByteFormat` use.
  public static let activationBytes: Int64 = 4_000_000_000
  public static let resolutionBytes: Int64 = 3_000_000_000

  public init() {}

  public func suggestion(for finding: Finding, state: RuleState) -> SuggestionContent? {
    guard finding.condition == DockVacSuite.reclaimableCondition,
      let bytes = finding.bytes(DockVacSuite.bytesEvidence)
    else { return nil }

    let threshold = state == .active ? Self.resolutionBytes : Self.activationBytes
    guard bytes >= threshold else { return nil }

    let endpoint = finding.scope.rawValue
    return SuggestionContent(
      title: "Docker is holding ~\(Self.roundedGigabytes(bytes)) GB you can rebuild",
      detail: """
        Untagged image leftovers and unused build cache at \(endpoint). Docker makes both \
        again on the next build, so removing them costs build time, never data. DockVac \
        selects them for review; nothing is removed until you confirm.
        """,
      route: DockVacSuite.reclaimRoute(endpoint: endpoint))
  }

  /// Whole gigabytes for a headline: 8.2 GB reads "~8 GB". Values below the resolution
  /// threshold never reach a headline, so this never says "~0 GB".
  static func roundedGigabytes(_ bytes: Int64) -> Int {
    Int((Double(bytes) / 1_000_000_000).rounded())
  }
}
