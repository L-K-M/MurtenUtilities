import AppKit
import SwiftUI
import XCTest
@testable import MurtenShell

@MainActor
final class HomeLayoutTests: XCTestCase {
    func testHomeFitsDefaultWindowWithoutVerticalOverflow() async throws {
        // Also cover the content area of a restored 720-point window.
        let layout = try await measureHome(height: 688)
        XCTAssertLessThanOrEqual(layout.documentHeight, layout.viewportHeight + 1,
                                 "All ten tools must fit inside the default home window")
        XCTAssertTrue(layout.scrollerHidden, "The scrollbar should disappear when the content fits")
    }

    func testHomeStillScrollsWhenTheWindowIsMadeSmaller() async throws {
        let layout = try await measureHome(height: 600)
        XCTAssertGreaterThan(layout.documentHeight, layout.viewportHeight)
        XCTAssertFalse(layout.scrollerHidden, "A smaller window must keep the tools reachable")
    }

    private func measureHome(height: CGFloat) async throws
        -> (documentHeight: CGFloat, viewportHeight: CGFloat, scrollerHidden: Bool) {
        let harness = Harness(withWatcher: false)
        // Erase the internal view type before retaining the host across await.
        let host = NSHostingView<AnyView>(rootView: AnyView(HomeView(model: harness.model)))
        host.frame = NSRect(x: 0, y: 0, width: 1040, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(descendants(of: host).compactMap { $0 as? NSScrollView }.first)
        let document = try XCTUnwrap(scroll.documentView)
        let loaded = await eventually {
            host.layoutSubtreeIfNeeded()
            return document.frame.height > 500
        }
        XCTAssertTrue(loaded, "The full tool grid must be laid out before measuring it")
        return (document.frame.height, scroll.contentView.bounds.height,
                try XCTUnwrap(scroll.verticalScroller).isHidden)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
