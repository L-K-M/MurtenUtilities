import SwiftUI
import AppKit
import RigiUI

/// Bridges Rigi's engraved status bar into the SwiftUI home window — the first
/// piece of classic chrome the suite uses, and proof the pinned RigiUI
/// dependency is wired end to end.
struct StatusBar: NSViewRepresentable {
    let message: String

    func makeNSView(context: Context) -> StatusBarView {
        StatusBarView(frame: .zero)
    }

    func updateNSView(_ nsView: StatusBarView, context: Context) {
        nsView.message = message
    }
}
