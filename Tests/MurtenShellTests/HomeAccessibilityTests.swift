import AppKit
import SwiftUI
import XCTest
import MurtenCore
@testable import MurtenShell

/// The home grid as assistive technology sees it. VoiceOver, Voice Control
/// and Switch Control open a tool with the accessibility press action, not
/// with a mouse click, so a tile that only looks like a button is a dead end.
@MainActor
final class HomeAccessibilityTests: XCTestCase {
    func testAvailableTileOpensWithTheAccessibilityPressAction() throws {
        let probe = try TileProbe(state: .available)
        defer { probe.close() }

        let tile = try XCTUnwrap(probe.tile(), "the tile must be exposed under the tool's name")
        XCTAssertEqual(tile.role, NSAccessibility.Role.button.rawValue)
        XCTAssertTrue(tile.press(), "the tile must offer a press action")
        XCTAssertEqual(probe.timesOpened, 1)
    }

    func testUnavailableTileSaysWhyAndDoesNotOpen() throws {
        let probe = try TileProbe(state: .inapplicable("Docker is not installed"))
        defer { probe.close() }

        let tile = try XCTUnwrap(probe.tile())
        XCTAssertEqual(tile.value, "Unavailable: Docker is not installed")
        _ = tile.press()
        XCTAssertEqual(probe.timesOpened, 0)
    }

    /// One SwiftUI accessibility node. SwiftUI's nodes are plain objects
    /// that answer the NSAccessibility selectors without declaring the
    /// protocol, so they are queried by selector.
    private struct Node {
        let object: NSObject

        var label: String? { string("accessibilityLabel") }
        var role: String? { string("accessibilityRole") }
        var value: String? { string("accessibilityValue") }

        var children: [Node] {
            let selector = NSSelectorFromString("accessibilityChildren")
            guard object.responds(to: selector),
                  let list = object.perform(selector)?.takeUnretainedValue() as? [Any] else { return [] }
            return list.compactMap { ($0 as? NSObject).map(Node.init) }
        }

        /// What VoiceOver's "press" does; false when the node has no such action.
        func press() -> Bool {
            let selector = NSSelectorFromString("accessibilityPerformPress")
            guard object.responds(to: selector) else { return false }
            typealias Press = @convention(c) (AnyObject, Selector) -> Bool
            return unsafeBitCast(object.method(for: selector), to: Press.self)(object, selector)
        }

        func first(named name: String, depth: Int = 0) -> Node? {
            if label == name { return self }
            guard depth < 12 else { return nil }
            for child in children {
                if let match = child.first(named: name, depth: depth + 1) { return match }
            }
            return nil
        }

        private func string(_ selectorName: String) -> String? {
            let selector = NSSelectorFromString(selectorName)
            guard object.responds(to: selector) else { return nil }
            return object.perform(selector)?.takeUnretainedValue() as? String
        }
    }

    /// Hosts one tile in an off-screen window and finds its accessibility node.
    @MainActor
    private final class TileProbe {
        private final class Counter { var count = 0 }

        private let module: SuiteModule
        private let counter = Counter()
        private let host: NSView
        private let window: NSWindow

        var timesOpened: Int { counter.count }

        init(state: ModuleTile.TileState) throws {
            let module = try XCTUnwrap(ModuleRegistry.all.first)
            self.module = module
            Self.activateAccessibility()

            let counter = self.counter
            let tile = ModuleTile(module: module, state: state) { counter.count += 1 }
            let host: NSView = NSHostingView(rootView: tile.frame(width: 240, height: 200))
            host.frame = NSRect(x: 0, y: 0, width: 240, height: 200)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            self.host = host
            self.window = window
        }

        func tile() -> Node? {
            Node(object: host).first(named: module.name)
        }

        func close() {
            window.close()
        }

        /// SwiftUI builds its accessibility tree only once an assistive
        /// client has announced itself. Setting AXEnhancedUserInterface is
        /// how such a client does that; here the test plays the client.
        private static func activateAccessibility() {
            let selector = NSSelectorFromString("accessibilitySetValue:forAttribute:")
            let application = NSApplication.shared
            guard application.responds(to: selector) else { return }
            application.perform(selector, with: true, with: "AXEnhancedUserInterface")
        }
    }
}
