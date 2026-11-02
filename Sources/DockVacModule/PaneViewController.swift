import AppKit
import DockVacCore
import DockVacDocker
import RigiUI

/// The pane's AppKit side, built anew each time the suite shows DockVac: a Rigi bar with
/// what was the standalone window's toolbar and subtitle, a strip for what a suggestion
/// did, and the content view for the current phase. All state lives in `AppController`.
final class PaneViewController: NSViewController {
  weak var controller: AppController?
  var onDismissNotice: (() -> Void)?

  let scanningView = ScanningView(frame: .zero)
  let reportView = ReportView(frame: .zero)
  let messageView = MessageView(frame: .zero)
  private let contentArea = NSView()
  private var currentContent: NSView?

  private let backButton = PaneViewController.symbolButton(
    "chevron.left", title: "Back", help: "Back to the overview (⌘↑)")
  private let rescanButton = PaneViewController.symbolButton(
    "arrow.clockwise", title: "Rescan", help: "Scan Docker again (⌘R)")
  private let connectionButton = PaneViewController.symbolButton(
    "network", title: "Connect via SSH", help: "Connect to Docker on a server via SSH (⌘K)")
  private let connectionLabel = Theme.label("", size: 11, color: .secondaryLabelColor)
  private let filterControl = ClassicToolControl(frame: .zero)
  private let reviewButton = ClassicToolbarButton(frame: .zero)
  private let noticeBar = ClassicBarView(style: .panel)
  private let noticeLabel = Theme.label("", size: 11)
  private let noticeDismiss = PaneViewController.symbolButton(
    "xmark", title: "Dismiss", help: "Hide this note")
  /// Zero while there is no notice, so the strip takes no room.
  private lazy var noticeHeight = noticeBar.heightAnchor.constraint(equalToConstant: 0)
  private static let noticeBarHeight: CGFloat = 28

  override func loadView() {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 1040, height: 640))
    let bar = makeBar()
    makeNoticeBar()
    contentArea.translatesAutoresizingMaskIntoConstraints = false
    for part in [bar, noticeBar, contentArea] {
      root.addSubview(part)
      NSLayoutConstraint.activate([
        part.leadingAnchor.constraint(equalTo: root.leadingAnchor),
        part.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      ])
    }
    NSLayoutConstraint.activate([
      bar.topAnchor.constraint(equalTo: root.topAnchor),
      bar.heightAnchor.constraint(equalToConstant: ClassicMetrics.toolbarHeight),
      noticeBar.topAnchor.constraint(equalTo: bar.bottomAnchor),
      noticeHeight,
      contentArea.topAnchor.constraint(equalTo: noticeBar.bottomAnchor),
      contentArea.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])
    view = root
  }

  // MARK: - Content

  func show(_ content: NSView) {
    if currentContent === content { return }
    currentContent?.removeFromSuperview()
    content.translatesAutoresizingMaskIntoConstraints = false
    contentArea.addSubview(content)
    NSLayoutConstraint.activate([
      content.topAnchor.constraint(equalTo: contentArea.topAnchor),
      content.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
      content.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
    ])
    currentContent = content
    if content === reportView {
      view.window?.makeFirstResponder(reportView.treemap)
    }
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    // The report may have been shown before the view had a window.
    if currentContent === reportView {
      view.window?.makeFirstResponder(reportView.treemap)
    }
  }

  /// The standalone app's toolbar validation, now pushed by the controller.
  func apply(_ state: ChromeState) {
    connectionLabel.stringValue = state.connectionSummary
    connectionLabel.toolTip = state.connectionSummary.isEmpty ? nil : state.connectionSummary
    filterControl.selectedSegment = state.filter.rawValue
    filterControl.isEnabled = state.canFilter
    backButton.isEnabled = state.canGoBack
    rescanButton.isEnabled = state.canRescan
    connectionButton.isEnabled = state.canChangeConnection
    reviewButton.isEnabled = state.canReview

    noticeLabel.stringValue = state.notice ?? ""
    noticeLabel.toolTip = state.notice
    noticeBar.isHidden = state.notice == nil
    noticeHeight.constant = state.notice == nil ? 0 : Self.noticeBarHeight
  }

  // MARK: - Bar

  private func makeBar() -> NSView {
    let bar = ClassicBarView(style: .toolbar)
    bar.translatesAutoresizingMaskIntoConstraints = false

    backButton.target = self
    backButton.action = #selector(backPressed)
    rescanButton.target = self
    rescanButton.action = #selector(rescanPressed)
    connectionButton.target = self
    connectionButton.action = #selector(connectionPressed)

    connectionLabel.setAccessibilityLabel("Connection")
    connectionLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

    filterControl.segmentCount = ReportFilter.allCases.count
    for filter in ReportFilter.allCases {
      filterControl.setLabel(filter.title, forSegment: filter.rawValue)
      filterControl.setWidth(88, forSegment: filter.rawValue)
    }
    filterControl.trackingMode = .selectOne
    filterControl.selectedSegment = ReportFilter.everything.rawValue
    filterControl.target = self
    filterControl.action = #selector(filterChanged)
    filterControl.toolTip = "Show everything, or only what can be removed (⌘1, ⌘2)"
    filterControl.setAccessibilityLabel("Show")

    reviewButton.title = "Review & Remove"
    reviewButton.toolTip = "Review the selected items and remove them (⌘↩)"
    reviewButton.target = self
    reviewButton.action = #selector(reviewPressed)

    let leading = NSStackView(views: [
      backButton, rescanButton, connectionButton, EtchedSeparatorView(), connectionLabel,
    ])
    leading.orientation = .horizontal
    leading.alignment = .centerY
    leading.spacing = ClassicMetrics.controlSpacing

    for view in [leading, filterControl, reviewButton] {
      view.translatesAutoresizingMaskIntoConstraints = false
      bar.addSubview(view)
    }
    let inset = ClassicMetrics.horizontalInset
    let centered = filterControl.centerXAnchor.constraint(equalTo: bar.centerXAnchor)
    // A long connection summary pushes the filter right rather than under it.
    centered.priority = .defaultHigh
    NSLayoutConstraint.activate([
      leading.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: inset),
      leading.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
      filterControl.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
      centered,
      filterControl.leadingAnchor.constraint(
        greaterThanOrEqualTo: leading.trailingAnchor, constant: ClassicMetrics.controlSpacing),
      reviewButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -inset),
      reviewButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
      reviewButton.leadingAnchor.constraint(
        greaterThanOrEqualTo: filterControl.trailingAnchor, constant: ClassicMetrics.controlSpacing),
    ])
    return bar
  }

  private func makeNoticeBar() {
    noticeBar.translatesAutoresizingMaskIntoConstraints = false
    noticeBar.isHidden = true
    noticeLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    noticeDismiss.target = self
    noticeDismiss.action = #selector(dismissPressed)

    let icon = NSImageView()
    icon.image = Theme.symbol("info.circle", pointSize: 12, color: .secondaryLabelColor)
    icon.setAccessibilityElement(false)

    let row = NSStackView(views: [icon, noticeLabel, noticeDismiss])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = ClassicMetrics.controlSpacing
    row.translatesAutoresizingMaskIntoConstraints = false
    noticeBar.addSubview(row)
    let inset = ClassicMetrics.horizontalInset
    NSLayoutConstraint.activate([
      row.leadingAnchor.constraint(equalTo: noticeBar.leadingAnchor, constant: inset),
      row.trailingAnchor.constraint(equalTo: noticeBar.trailingAnchor, constant: -inset),
      row.centerYAnchor.constraint(equalTo: noticeBar.centerYAnchor),
    ])
  }

  /// A Rigi bezel button that draws only its symbol; the title is what VoiceOver reads.
  private static func symbolButton(_ symbol: String, title: String, help: String)
    -> ClassicToolbarButton
  {
    let button = ClassicToolbarButton(frame: .zero)
    button.title = title
    button.image = Theme.symbol(symbol, pointSize: 12, weight: .medium)
    button.imagePosition = .imageOnly
    button.toolTip = help
    return button
  }

  // MARK: - Actions

  @objc private func backPressed() {
    controller?.focus(on: nil)
  }

  @objc private func rescanPressed() {
    controller?.rescan(nil)
  }

  @objc private func connectionPressed() {
    controller?.connectViaSSH(nil)
  }

  @objc private func reviewPressed() {
    controller?.reviewAndRemove()
  }

  @objc private func filterChanged() {
    guard let filter = ReportFilter(rawValue: filterControl.selectedSegment) else { return }
    controller?.setFilter(filter)
  }

  @objc private func dismissPressed() {
    onDismissNotice?()
  }
}
