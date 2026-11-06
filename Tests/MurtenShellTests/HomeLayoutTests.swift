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

    private func measureHome(height: CGFloat) async throws -> Measurement {
        let probe = try LayoutProbe(height: height)
        defer { probe.close() }
        let loaded = await eventually { probe.isReady() }
        XCTAssertTrue(loaded, "The full tool grid must be laid out before measuring it")
        return try probe.measurement()
    }

    private struct Measurement {
        let documentHeight: CGFloat
        let viewportHeight: CGFloat
        let scrollerHidden: Bool
    }

    /// Keep native view state in synchronous methods, outside the async frame.
    @MainActor
    private final class LayoutProbe {
        private let harness: Harness
        private let host: NSView
        private let window: NSWindow
        private let scroll: NSScrollView
        private let document: NSView

        init(height: CGFloat) throws {
            let harness = Harness(withWatcher: false)
            let host: NSView = NSHostingView(rootView: HomeView(model: harness.model))
            host.frame = NSRect(x: 0, y: 0, width: 1040, height: height)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .resizable],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.layoutSubtreeIfNeeded()

            let scroll: NSScrollView
            let document: NSView
            do {
                scroll = try XCTUnwrap(Self.descendants(of: host).compactMap { $0 as? NSScrollView }.first)
                document = try XCTUnwrap(scroll.documentView)
            } catch {
                window.close()
                throw error
            }
            self.harness = harness
            self.host = host
            self.window = window
            self.scroll = scroll
            self.document = document
        }

        func isReady() -> Bool {
            host.layoutSubtreeIfNeeded()
            return document.frame.height > 500
        }

        func measurement() throws -> Measurement {
            let scroller = try XCTUnwrap(scroll.verticalScroller)
            return Measurement(documentHeight: document.frame.height,
                               viewportHeight: scroll.contentView.bounds.height,
                               scrollerHidden: scroller.isHidden)
        }

        func close() {
            window.close()
        }

        private static func descendants(of view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants(of: $0) }
        }
    }
}
