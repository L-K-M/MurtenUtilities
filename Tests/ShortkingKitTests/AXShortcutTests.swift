import ApplicationServices
import Foundation
import XCTest
import ShortkingCore
@testable import ShortkingKit

final class AXShortcutTests: XCTestCase {
    private static let upArrowCharacter = "\u{F700}"
    private static let deleteCharacter = "\u{7F}"
    private static let deleteLeftGlyph = 0x17

    func testSpecialCharactersFallBackToVirtualKey() throws {
        let element = AXUIElementCreateApplication(getpid())
        let samples = [(Self.upArrowCharacter, "up"), (Self.deleteCharacter, "delete")]

        for (character, key) in samples {
            let keyCode = try XCTUnwrap(KeyCodes.keyCode(forToken: key))
            let attributes: [String: AnyObject] = [
                AXBridge.MenuAttribute.cmdChar: character as NSString,
                AXBridge.MenuAttribute.cmdVirtualKey: NSNumber(value: keyCode),
            ]
            let combo = AXBridge.shortcut(of: element) { _, name in attributes[name] }
            XCTAssertEqual(combo, KeyCombo(keyCode: keyCode, modifiers: .command))
        }
    }

    func testSpecialCharactersFallBackToGlyph() {
        let element = AXUIElementCreateApplication(getpid())
        let attributes: [String: AnyObject] = [
            AXBridge.MenuAttribute.cmdChar: Self.deleteCharacter as NSString,
            AXBridge.MenuAttribute.cmdGlyph: NSNumber(value: Self.deleteLeftGlyph),
        ]
        let combo = AXBridge.shortcut(of: element) { _, name in attributes[name] }
        XCTAssertEqual(combo, KeyCombo(token: "delete", modifiers: .command))
    }

    func testPrintableCharacterKeepsLayoutPrecedence() throws {
        let element = AXUIElementCreateApplication(getpid())
        let virtualKey = try XCTUnwrap(KeyCodes.keyCode(forToken: "y"))
        let attributes: [String: AnyObject] = [
            AXBridge.MenuAttribute.cmdChar: "z" as NSString,
            AXBridge.MenuAttribute.cmdVirtualKey: NSNumber(value: virtualKey),
        ]
        let combo = AXBridge.shortcut(of: element) { _, name in attributes[name] }
        XCTAssertEqual(combo, KeyCombo(character: "z", modifiers: .command))
    }
}
