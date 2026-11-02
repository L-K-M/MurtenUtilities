import AppKit
import SwiftUI

/// Reports the window hosting the pane, so the backup panels can open as
/// sheets on it. It only reads: the suite owns the window and its delegate,
/// which the standalone app's window connection used to take over.
struct HostingWindowReader: NSViewRepresentable {
    let found: (NSWindow) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.found = found
        return view
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {
        nsView.found = found
    }

    final class ReaderView: NSView {
        var found: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // Report after SwiftUI's update pass, not during it.
            DispatchQueue.main.async { [weak self] in self?.found?(window) }
        }
    }
}
