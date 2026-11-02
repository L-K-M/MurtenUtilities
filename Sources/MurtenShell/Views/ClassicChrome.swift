import AppKit
import SwiftUI
import RigiUI

/// Rigi's engraved status bar. Its built-in zoom cluster has no meaning in
/// the suite, so it is hidden rather than left as inert buttons
/// (docs/ui-direction.md, Accessibility acceptance).
struct StatusBar: NSViewRepresentable {
    let message: String

    func makeNSView(context: Context) -> StatusBarView {
        let view = StatusBarView(frame: .zero)
        view.subviews.filter { $0 is ClassicSegmentedControl }.forEach { $0.isHidden = true }
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.staticText)
        return view
    }

    func updateNSView(_ nsView: StatusBarView, context: Context) {
        nsView.message = message
        nsView.setAccessibilityLabel(message)
    }
}

/// Rigi's white inset well, the classic surface lists sit in.
struct InsetWell: NSViewRepresentable {
    func makeNSView(context: Context) -> ClassicInsetBox {
        ClassicInsetBox(frame: .zero)
    }

    func updateNSView(_ nsView: ClassicInsetBox, context: Context) {}
}

/// Rigi's polished platinum gradient, used behind the home window.
struct PlatinumBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> ClassicPanelView {
        ClassicPanelView(frame: .zero)
    }

    func updateNSView(_ nsView: ClassicPanelView, context: Context) {}
}
