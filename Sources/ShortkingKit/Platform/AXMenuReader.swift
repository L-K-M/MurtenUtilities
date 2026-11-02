import ApplicationServices
import Foundation
import ShortkingCore

/// Keeps every descendant read inside the same per-app deadline.
struct AXMenuReader {
    private let budget: MenuWalkBudget

    init(budget: MenuWalkBudget) {
        self.budget = budget
    }

    func menuBar(of application: AXUIElement) throws -> AXUIElement {
        guard let value = try read(application, kAXMenuBarAttribute as String),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw MenuWalkBudget.Incomplete.unavailable
        }
        return value as! AXUIElement
    }

    func children(of element: AXUIElement) throws -> [AXUIElement] {
        guard let value = try read(element, kAXChildrenAttribute as String) else { return [] }
        guard let children = value as? [AXUIElement] else {
            throw MenuWalkBudget.Incomplete.unavailable
        }
        return children
    }

    func title(of element: AXUIElement) throws -> String? {
        try read(element, kAXTitleAttribute as String) as? String
    }

    func shortcut(of element: AXUIElement) throws -> KeyCombo? {
        try AXBridge.shortcut(of: element, read: read)
    }

    func enabled(of element: AXUIElement) throws -> Bool {
        let number = try read(element, AXBridge.MenuAttribute.enabled) as? NSNumber
        return number.map { $0.intValue != 0 } ?? true
    }

    private func read(_ element: AXUIElement, _ attribute: String) throws -> CFTypeRef? {
        let timeout = try budget.readTimeout()
        guard AXUIElementSetMessagingTimeout(element, timeout) == .success else {
            throw MenuWalkBudget.Incomplete.unavailable
        }

        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        _ = try budget.readTimeout()

        switch result {
        case .success: return value
        case .attributeUnsupported, .noValue: return nil
        default: throw MenuWalkBudget.Incomplete.unavailable
        }
    }
}
