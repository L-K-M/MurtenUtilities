import AppKit
import DockVacCore
import DockVacDocker
import MurtenCore

/// Application state and every user action. Views render what it hands them and call
/// back through `ReportActions`; Docker work goes through `DockerService`.
///
/// In the suite the controller outlives its views: the provider keeps one for the app's
/// lifetime, and every time the suite builds the pane it attaches a fresh
/// `PaneViewController`. With no pane attached, actions still update state and the next
/// pane renders it.
@MainActor
final class AppController: NSObject, ReportActions, DockerServiceDelegate {
  /// The pane on screen, if any.
  private(set) weak var pane: PaneViewController?
  /// What the pane's bar and the suite's Tool menu offer right now.
  let chrome = PaneChrome()
  /// Called when a cleanup run ends, so the suite re-checks Docker sooner.
  var onCleanupFinished: (() -> Void)?
  private let service: DockerService

  private(set) var phase: AppPhase = .idle
  private(set) var report: UsageReport = .empty {
    didSet { automaticPlans = Self.plans(for: report) }
  }
  /// Rebuilt when the report changes rather than per render: planning a level walks
  /// every reclaimable resource, and `render()` runs on every click.
  private(set) var automaticPlans: [AutomaticCleanupLevel: CleanupPlan] = [:]
  private(set) var connection: DockerConnection?
  private var scanningConnection: DockerConnection?
  private var sshConnectionSheet: SSHConnectionSheetController?
  private(set) var focus: DockerResourceKind?
  private(set) var filter: ReportFilter = .everything
  private(set) var selectedItem: DockerResourceID?
  private(set) var selectedCategory: DockerResourceKind?
  private(set) var basket: Set<DockerResourceID> = []
  private var scanStartedAt: Date?
  private var scanTimer: Timer?
  private var confirmationSheet: ConfirmationSheetController?
  private var progressSheet: CleanupProgressSheetController?
  private var lastRunState: CleanupRunState?
  /// The suite window the confirmation sheet was attached to. The progress sheet uses
  /// it too, so a confirmed cleanup still shows its progress after the user navigated
  /// to another tool while the confirmation was up.
  private weak var sheetHost: NSWindow?
  /// Whether the first scan has started; the pane scans on first open, not at launch.
  private var started = false
  /// The endpoint a suggestion asked to reclaim, until the scan it started finishes.
  private var pendingPreselection: String?
  /// What opening a suggestion did, shown above the report until dismissed.
  private(set) var notice: String?
  /// False while SwiftUI is building the pane, when `chrome` must not change.
  private var publishesChrome = true

  var isCleaning: Bool { service.isCleaning }

  /// While the confirmation or progress sheet is up, the plan on screen must stay valid, so
  /// every other action is refused.
  var isSheetPresented: Bool {
    confirmationSheet != nil || progressSheet != nil || sshConnectionSheet != nil
  }

  private var displayedConnection: DockerConnection? {
    phase.isScanning ? scanningConnection : connection
  }

  init(service: DockerService = DockerService()) {
    self.service = service
    super.init()
    service.delegate = self
  }

  // MARK: - Pane

  func attach(_ pane: PaneViewController) {
    self.pane = pane
    pane.controller = self
    pane.reportView.actions = self
    pane.scanningView.onCancel = { [weak self] in self?.cancelScan() }
    pane.messageView.onAction = { [weak self] in self?.rescan(nil) }
    pane.onDismissNotice = { [weak self] in self?.dismissNotice() }
    // SwiftUI calls this while it builds the pane: draw the AppKit views now, and publish
    // the Tool menu's state once that update is over rather than in the middle of it.
    publishesChrome = false
    render()
    publishesChrome = true
    Task { @MainActor [weak self] in self?.refreshChrome() }
  }

  func detach(_ pane: PaneViewController) {
    guard self.pane === pane else { return }
    self.pane = nil
  }

  /// The pane appeared, opened by `route`: nil or a bare route for a tile click. The
  /// first opening scans. A reclaim route re-scans its endpoint and, once that scan
  /// completes, selects what Docker can rebuild there. It never starts a removal.
  func open(_ route: ModuleRoute?) {
    if let route, route.action == DockVacSuite.reclaimAction,
      let endpoint = route.context[DockVacSuite.endpointContext]
    {
      reclaim(endpoint: endpoint)
      return
    }
    guard !started else { return }
    rescan(nil)
  }

  private func reclaim(endpoint: String) {
    guard !service.isCleaning, !isSheetPresented else {
      notice =
        "Finish the cleanup or close the open sheet, then open the suggestion again. Nothing was selected."
      render()
      return
    }

    let target: DockerConnectionTarget
    if endpoint.lowercased().hasPrefix("\(DockerSSHHost.scheme)://") {
      guard let host = try? DockerSSHHost(endpoint) else {
        notice =
          "The suggestion names an endpoint DockVac cannot use (\(endpoint)). Nothing was selected."
        render()
        return
      }
      target = .ssh(host)
    } else {
      // The watcher found this socket through the automatic search; the same search
      // finds it again, and the scan below checks that it did.
      target = .automatic
    }
    selectConnection(target, preselectingFor: endpoint)
  }

  /// Selects the safe level, and only it, when the scan reached the suggestion's endpoint.
  /// The basket is replaced so the selection is exactly what the suggestion counted:
  /// containers, volumes and re-pullable images are never part of it.
  private func applyPreselection(for endpoint: String) {
    guard let connection, connection.endpoint.address == endpoint else {
      let reached = connection?.endpoint.address ?? "no daemon"
      notice =
        "The suggestion was for Docker at \(endpoint), but DockVac reached \(reached). Nothing was selected."
      return
    }
    let plan = automaticPlans[.safe] ?? .empty
    basket = Set(plan.operations.map(\.id))
    notice =
      plan.isEmpty
      ? "Nothing Docker can rebuild is left at \(endpoint)."
      : "Selected what Docker can rebuild: \(plan.summary), about \(ByteFormat.string(plan.estimatedReclaimableBytes)). Nothing is removed until you review and confirm."
  }

  func dismissNotice() {
    notice = nil
    render()
  }

  // MARK: - Derived state

  var displayedReport: UsageReport {
    switch filter {
    case .everything:
      return report
    case .reclaimable:
      return report.filtered {
        $0.removability.isRemovableNow || !$0.removability.prerequisites.isEmpty
      }
    }
  }

  var plan: CleanupPlan {
    CleanupPlan.make(selecting: basket, from: report)
  }

  private static func plans(for report: UsageReport)
    -> [AutomaticCleanupLevel: CleanupPlan]
  {
    Dictionary(
      uniqueKeysWithValues: AutomaticCleanupLevel.allCases.map {
        ($0, CleanupPlan.make(selecting: report.automaticCleanupIDs($0), from: report))
      })
  }

  private var viewState: ReportViewState {
    ReportViewState(
      report: displayedReport,
      fullReport: report,
      focus: focus,
      selectedItem: selectedItem,
      selectedCategory: selectedCategory,
      basket: basket,
      plan: plan,
      automaticPlans: automaticPlans,
      filter: filter,
      connection: connection
    )
  }

  // MARK: - Scanning

  @objc func rescan(_ sender: Any?) {
    guard !service.isCleaning, !isSheetPresented else { return }
    pendingPreselection = nil
    notice = nil
    startScan()
  }

  private func startScan() {
    guard !service.isCleaning, !isSheetPresented else { return }
    started = true
    phase = .connecting
    scanningConnection = nil
    scanStartedAt = Date()
    startScanTimer()
    service.scan()
    render()
  }

  func cancelScan() {
    service.cancelScan()
    stopScanTimer()
    if pendingPreselection != nil {
      pendingPreselection = nil
      notice = "The scan was cancelled, so the suggestion selected nothing."
    }
    phase = report.itemCount > 0 && report.capturedAt.timeIntervalSince1970 > 0 ? .report : .idle
    render()
  }

  private func startScanTimer() {
    stopScanTimer()
    scanTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.phase.isScanning else { return }
        self.pane?.scanningView.apply(
          phase: self.phase, connection: self.displayedConnection, target: self.service.target,
          startedAt: self.scanStartedAt)
      }
    }
  }

  private func stopScanTimer() {
    scanTimer?.invalidate()
    scanTimer = nil
  }

  func serviceDidConnect(_ connection: DockerConnection) {
    scanningConnection = connection
    phase = .scanning(nil)
    render()
  }

  func serviceDidReportScanProgress(_ progress: ScanProgress) {
    guard phase.isScanning else { return }
    phase = .scanning(progress)
    render()
  }

  func serviceDidFinishScan(_ result: Result<DockerDiskUsage, Error>) {
    stopScanTimer()
    switch result {
    case .success(let usage):
      // Resource IDs are daemon-local. Never carry a selection to another server.
      if connection?.endpoint != service.connection?.endpoint {
        basket.removeAll()
        selectedItem = nil
        selectedCategory = nil
        focus = nil
      }
      connection = service.connection
      report = UsageAnalyzer.analyze(usage)
      basket = basket.filter { report.item(for: $0) != nil }
      if let selectedItem, report.item(for: selectedItem) == nil {
        self.selectedItem = nil
      }
      if let focus, report.category(for: focus) == nil {
        self.focus = nil
      }
      phase = .report
      if let endpoint = pendingPreselection {
        pendingPreselection = nil
        applyPreselection(for: endpoint)
      }
    case .failure(let error):
      if pendingPreselection != nil {
        pendingPreselection = nil
        notice = "The scan did not finish, so the suggestion selected nothing."
      }
      if error is CancellationError {
        phase = report.capturedAt.timeIntervalSince1970 > 0 ? .report : .idle
      } else {
        let title: String
        if let engineError = error as? DockerEngineError, case .daemonNotFound = engineError {
          title = "Docker isn't running"
        } else {
          title = "Couldn't read Docker"
        }
        phase = .failed(title: title, message: dockerErrorMessage(error))
      }
    }
    render()
  }

  // MARK: - Connections

  @objc func connectViaSSH(_ sender: Any?) {
    guard !isSheetPresented, !service.isCleaning, let window = pane?.view.window else {
      return
    }
    cancelScan()
    let host: DockerSSHHost?
    if case .ssh(let selected) = service.target {
      host = selected
    } else if let connection, case .ssh(let connected) = connection.endpoint.transport {
      host = connected
    } else {
      host = nil
    }
    let sheet = SSHConnectionSheetController(host: host) { [weak self] host in
      guard let self else { return }
      self.sshConnectionSheet = nil
      if let host {
        self.selectConnection(.ssh(host))
      } else {
        self.render()
      }
    }
    sshConnectionSheet = sheet
    if let sheetWindow = sheet.window { window.beginSheet(sheetWindow) { _ in } }
    render()
  }

  @objc func useLocalDocker(_ sender: Any?) {
    guard !isSheetPresented, !service.isCleaning else { return }
    selectConnection(.local)
  }

  private func selectConnection(
    _ target: DockerConnectionTarget, preselectingFor endpoint: String? = nil
  ) {
    service.selectTarget(target)
    connection = nil
    scanningConnection = nil
    report = .empty
    basket.removeAll()
    selectedItem = nil
    selectedCategory = nil
    focus = nil
    pendingPreselection = endpoint
    notice = nil
    startScan()
  }

  // MARK: - ReportActions

  func select(item id: DockerResourceID?) {
    selectedItem = id
    if id != nil {
      selectedCategory = id?.kind
    }
    render()
  }

  func select(category kind: DockerResourceKind?) {
    selectedCategory = kind
    selectedItem = nil
    render()
  }

  func focus(on kind: DockerResourceKind?) {
    guard phase == .report, !isSheetPresented else { return }
    focus = kind
    if let kind {
      selectedCategory = kind
      if let selectedItem, selectedItem.kind != kind {
        self.selectedItem = nil
      }
    }
    render()
  }

  func toggleBasket(_ id: DockerResourceID) {
    guard !isSheetPresented else { return }
    if basket.contains(id) {
      removeFromBasket([id])
    } else {
      addToBasket([id])
    }
  }

  func addToBasket(_ ids: [DockerResourceID]) {
    guard !isSheetPresented else { return }
    let additions = report.selectionClosure(ids).filter {
      report.item(for: $0)?.removability.isBlocked == false
    }
    basket.formUnion(additions)
    render()
  }

  func removeFromBasket(_ ids: [DockerResourceID]) {
    guard !isSheetPresented else { return }
    basket.subtract(ids)
    // Items that needed one of the removed prerequisites cannot stay either.
    for id in basket {
      if let item = report.item(for: id),
        item.removability.prerequisites.contains(where: { ids.contains($0) })
      {
        basket.remove(id)
      }
    }
    render()
  }

  func clearBasket() {
    guard !isSheetPresented else { return }
    basket.removeAll()
    render()
  }

  func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  func setFilter(_ newFilter: ReportFilter) {
    guard !isSheetPresented else { return }
    filter = newFilter
    if let selectedItem, displayedReport.item(for: selectedItem) == nil {
      self.selectedItem = nil
    }
    render()
  }

  // MARK: - Cleanup

  func reviewAndRemove() {
    confirm(plan)
  }

  /// Confirms everything Docker can produce again at `level`. The cleanup list is left
  /// alone: what the user confirms is exactly the reproducible set, never a volume they
  /// ticked earlier, and their own selection survives if they cancel.
  func runAutomaticCleanup(_ level: AutomaticCleanupLevel) {
    confirm(automaticPlans[level] ?? .empty)
  }

  private func confirm(_ plan: CleanupPlan) {
    guard phase == .report, !service.isCleaning, !isSheetPresented,
      let window = pane?.view.window, let connection
    else { return }
    guard !plan.isEmpty || !plan.exclusions.isEmpty else { return }
    let sheet = ConfirmationSheetController(
      plan: plan, connection: connection, equivalentCommands: service.equivalentCommands(for: plan)
    ) {
      [weak self] confirmed in
      guard let self else { return }
      self.confirmationSheet = nil
      if confirmed, !plan.isEmpty {
        self.runCleanup(plan)
      } else {
        self.refreshChrome()
      }
    }
    confirmationSheet = sheet
    sheetHost = window
    if let sheetWindow = sheet.window {
      window.beginSheet(sheetWindow) { _ in }
    }
    refreshChrome()
  }

  private func runCleanup(_ plan: CleanupPlan) {
    guard let window = sheetHost ?? pane?.view.window else {
      refreshChrome()
      return
    }
    let initial = CleanupRunState(plan: plan)
    lastRunState = initial
    let sheet = CleanupProgressSheetController(
      state: initial,
      onStop: { [weak self] in self?.service.stopCleanup() },
      onDone: { [weak self] in
        guard let self else { return }
        self.progressSheet = nil
        if let finished = self.lastRunState {
          for (operation, status) in zip(finished.plan.operations, finished.statuses) {
            if case .succeeded = status {
              self.basket.remove(operation.id)
            }
          }
        }
        self.rescan(nil)
      })
    progressSheet = sheet
    if let sheetWindow = sheet.window {
      window.beginSheet(sheetWindow) { _ in }
    }
    service.runCleanup(plan)
    refreshChrome()
  }

  func serviceDidReportCleanupProgress(_ state: CleanupRunState) {
    lastRunState = state
    progressSheet?.apply(state)
  }

  func serviceDidFinishCleanup(_ state: CleanupRunState) {
    lastRunState = state
    progressSheet?.apply(state)
    refreshChrome()
    onCleanupFinished?()
  }

  // MARK: - Menu actions

  @objc func goBack(_ sender: Any?) {
    focus(on: nil)
  }

  @objc func showEverything(_ sender: Any?) {
    setFilter(.everything)
  }

  @objc func showReclaimable(_ sender: Any?) {
    setFilter(.reclaimable)
  }

  @objc func toggleSelectedInBasket(_ sender: Any?) {
    guard let selectedItem else { return }
    toggleBasket(selectedItem)
  }

  @objc func addSafeItems(_ sender: Any?) {
    addToBasket(report.automaticCleanupIDs(.safe))
  }

  @objc func automaticCleanupSafe(_ sender: Any?) {
    runAutomaticCleanup(.safe)
  }

  @objc func automaticCleanupThorough(_ sender: Any?) {
    runAutomaticCleanup(.thorough)
  }

  @objc func clearBasketAction(_ sender: Any?) {
    clearBasket()
  }

  @objc func reviewAndRemoveAction(_ sender: Any?) {
    reviewAndRemove()
  }

  @objc func openHelp(_ sender: Any?) {
    if let url = URL(string: "https://github.com/L-K-M/dockvac") {
      NSWorkspace.shared.open(url)
    }
  }

  /// What the pane's bar and the Tool menu may offer: the rules the standalone app's
  /// toolbar and menu validation applied.
  private func makeChromeState() -> ChromeState {
    let idle = !isSheetPresented
    let inReport = idle && phase == .report && !service.isCleaning
    let selected = selectedItem.flatMap { report.item(for: $0) }
    return ChromeState(
      connectionSummary: displayedConnection?.summary ?? "",
      filter: filter,
      canFilter: idle && phase == .report,
      canGoBack: inReport && focus != nil,
      canRescan: idle && !phase.isScanning && !service.isCleaning,
      canChangeConnection: idle && !service.isCleaning,
      canToggleSelected: inReport && selected?.removability.isBlocked == false,
      selectedIsInBasket: selectedItem.map { basket.contains($0) } ?? false,
      canAddSafe: inReport && automaticPlans[.safe]?.isEmpty == false,
      canCleanUpSafe: inReport && automaticPlans[.safe]?.isEmpty == false,
      canCleanUpThorough: inReport && automaticPlans[.thorough]?.isEmpty == false,
      canClearBasket: inReport && !basket.isEmpty,
      canReview: inReport && !basket.isEmpty,
      notice: notice)
  }

  private func refreshChrome() {
    let state = makeChromeState()
    pane?.apply(state)
    // Observation notifies on every assignment; only a real change should rebuild the
    // Tool menu.
    guard publishesChrome, chrome.state != state else { return }
    chrome.state = state
  }

  // MARK: - Rendering

  private func render() {
    defer { refreshChrome() }
    guard let pane else { return }
    switch phase {
    case .idle:
      pane.messageView.apply(
        icon: Theme.dockVacIcon,
        headline: "Ready to scan Docker",
        message:
          "DockVac shows what Docker keeps on disk and lets you remove exactly the pieces you choose. Nothing is deleted without your confirmation.",
        details: "",
        action: "Scan Docker")
      pane.show(pane.messageView)
    case .connecting, .scanning:
      pane.scanningView.apply(
        phase: phase, connection: displayedConnection, target: service.target,
        startedAt: scanStartedAt)
      pane.show(pane.scanningView)
    case .report:
      pane.reportView.apply(viewState)
      pane.show(pane.reportView)
    case .failed(let title, let message):
      let (body, details) = splitErrorMessage(message)
      pane.messageView.apply(
        icon: Theme.symbol(
          "exclamationmark.triangle", pointSize: 72, weight: .light, color: .systemOrange),
        headline: title,
        message: body.isEmpty
          ? "Start Docker Desktop (or OrbStack, Colima, Rancher Desktop) and try again." : body,
        details: details,
        action: "Try Again")
      pane.show(pane.messageView)
    }
  }

  /// The first line is the headline explanation; the rest are the technical details.
  private func splitErrorMessage(_ message: String) -> (String, String) {
    var lines = message.components(separatedBy: "\n")
    guard !lines.isEmpty else { return ("", "") }
    let first = lines.removeFirst()
    return (first, lines.joined(separator: "\n"))
  }
}
