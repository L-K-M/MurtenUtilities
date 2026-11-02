import DockVacCore
import Observation

/// Everything the pane's bar and the suite's Tool menu show besides the report itself:
/// what the standalone app's toolbar, window subtitle and menu validation covered.
struct ChromeState: Equatable {
  /// The daemon the report came from, e.g. "Docker Desktop · Docker Engine 29.3.1".
  var connectionSummary = ""
  var filter: ReportFilter = .everything
  var canFilter = false
  var canGoBack = false
  var canRescan = false
  var canChangeConnection = false
  var canToggleSelected = false
  var selectedIsInBasket = false
  var canAddSafe = false
  var canCleanUpSafe = false
  var canCleanUpThorough = false
  var canClearBasket = false
  var canReview = false
  /// What opening a suggestion did, until the user dismisses it.
  var notice: String?
}

/// Publishes `ChromeState` to SwiftUI, so the Tool menu's commands follow the pane.
@MainActor
@Observable
final class PaneChrome {
  var state = ChromeState()
}
