import SwiftUI

/// A request for one of a module's auxiliary windows, e.g. DeviceControlDoctor's
/// Test Pad or a RunningMan job log. The shell owns a single window group
/// for these; the module builds the content.
///
///     @Environment(\.openWindow) private var openWindow
///     openWindow(module: ModuleWindowRequest(moduleID: "devicecontroldoctor", kind: "test-pad"))
public struct ModuleWindowRequest: Codable, Hashable, Sendable {
    /// The shell's window-group id for module windows.
    public static let windowGroupID = "module-window"

    public let moduleID: String
    /// Module-defined window kind, e.g. "test-pad".
    public let kind: String
    /// Optional identifier inside the kind, e.g. a runner id.
    public let item: String?

    public init(moduleID: String, kind: String, item: String? = nil) {
        self.moduleID = moduleID
        self.kind = kind
        self.item = item
    }
}

public extension OpenWindowAction {
    /// Opens (or brings forward) a module's auxiliary window.
    func callAsFunction(module request: ModuleWindowRequest) {
        callAsFunction(id: ModuleWindowRequest.windowGroupID, value: request)
    }
}

/// A command the focused pane offers in the suite's Tool menu, with its
/// keyboard shortcut. Panes publish them with `.moduleCommands(_:)`.
public struct ModuleCommand: Identifiable {
    /// Whether the item carries a checkmark, e.g. DockVac's active filter.
    public enum CheckState: Sendable {
        /// An ordinary command.
        case none
        case checked
        case unchecked
    }

    public let id: String
    public let title: String
    public let shortcut: KeyboardShortcut?
    public let isEnabled: Bool
    public let checkState: CheckState
    /// The item's tooltip.
    public let help: String?
    /// Consecutive commands with different groups get a divider between them.
    public let group: String?
    public let action: @MainActor () -> Void

    public init(_ title: String, id: String? = nil, shortcut: KeyboardShortcut? = nil, isEnabled: Bool = true,
                checkState: CheckState = .none, help: String? = nil, group: String? = nil,
                action: @escaping @MainActor () -> Void) {
        self.id = id ?? title
        self.title = title
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.checkState = checkState
        self.help = help
        self.group = group
        self.action = action
    }
}

/// The focused pane's commands; an array per pane, nil when no pane is focused.
public struct ModuleCommandsKey: FocusedValueKey {
    public typealias Value = [ModuleCommand]
}

public extension FocusedValues {
    var moduleCommands: [ModuleCommand]? {
        get { self[ModuleCommandsKey.self] }
        set { self[ModuleCommandsKey.self] = newValue }
    }
}

public extension View {
    /// Publishes the pane's commands to the suite's Tool menu while the
    /// pane's window is key.
    func moduleCommands(_ commands: [ModuleCommand]) -> some View {
        focusedSceneValue(\.moduleCommands, commands)
    }
}
