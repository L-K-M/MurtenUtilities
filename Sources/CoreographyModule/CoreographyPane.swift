import SwiftUI
import MurtenCore
import MurtenModuleKit
import CoreographyCore
import CoreographyServices

/// The pane: the standalone app's monitor window inside the suite. It
/// applies the route it opened with once, keeps sampling on while it shows,
/// and publishes the app's menu commands to the suite's Tool menu.
struct CoreographyPane: View {
    let session: CoreographySession
    let route: ModuleRoute?
    /// The pane is rebuilt for every route, so applying once per view is
    /// applying once per click.
    @State private var routeApplied = false

    var body: some View {
        DashboardView(model: session.model, hud: session.hud)
            .modifier(MCPApprovalAlert(access: session.mcpAccess))
            .environment(\.coreographyHelperUnavailable, HelperAvailability.reason(session.helperAccess.state))
            .moduleCommands(commands)
            .onAppear {
                if !routeApplied {
                    routeApplied = true
                    CoreographyNavigation.apply(route, to: session.model)
                }
                session.appeared(.pane)
            }
            .onDisappear { session.disappeared(.pane) }
            .task { await session.helperAccess.refresh() }
    }

    /// The standalone app's View menu commands, now in the Tool menu while
    /// the pane is focused.
    private var commands: [ModuleCommand] {
        let model = session.model
        let hud = session.hud
        return [
            ModuleCommand(hud.isShown ? "Hide HUD" : "Show HUD", id: "hud",
                          shortcut: KeyboardShortcut("h", modifiers: [.command, .control])) { hud.toggle() },
            ModuleCommand("Change HUD Detail", shortcut: KeyboardShortcut("j", modifiers: [.command, .control])) {
                hud.cycleDensity()
            },
            ModuleCommand("Open Recording…", shortcut: KeyboardShortcut("o", modifiers: .command)) {
                RecordingOpener.choose(into: model)
            },
            ModuleCommand("Return to Now", shortcut: KeyboardShortcut("0", modifiers: .command)) {
                model.returnToNow()
                model.navigate(to: .timeline)
            },
            ModuleCommand("Command Palette…", shortcut: KeyboardShortcut("p", modifiers: [.command, .shift])) {
                model.paletteShown = true
            }
        ]
    }
}

/// What a route does to the pane: navigation only. It may open a section
/// and filter or sort its process table; it never selects a row, arms an
/// action, starts a space survey or signals a process (docs/modules.md,
/// preselection).
@MainActor
enum CoreographyNavigation {
    static func apply(_ route: ModuleRoute?, to model: DashboardModel) {
        guard let route, route.moduleID == CoreographyWatch.moduleID, let action = route.action else { return }

        switch action {
        case CoreographyWatch.Action.process:
            model.navigate(to: .processes)
            model.processSort = .cpu
            model.processFilter = route.context[CoreographyWatch.nameContextKey] ?? ""
        case CoreographyWatch.Action.memory:
            // The memory lane above the process table, biggest first.
            model.navigate(to: .memory)
            model.processSort = .memory
        case CoreographyWatch.Action.thermal:
            // Power and thermal lanes above the sensors.
            model.navigate(to: .power)
        case CoreographyWatch.Action.storage:
            // The disk lane, whose startup volume opens into where its
            // space goes, above the process table by disk writes.
            model.navigate(to: .storage)
            model.processSort = .diskWrite
        default:
            break
        }
    }
}

/// Features that need the privileged helper say why they are unavailable:
/// a short reason on each control, the explanation once in the pane.
enum HelperAvailability {
    static let explanation = String(localized: "Needs a signed build: this copy of Murten Utilities is not signed with a Developer ID, so Coreography's privileged helper cannot run. Other users' processes, spindump, raising priority and login items stay unavailable.")

    static func reason(_ state: HelperInstallState?) -> String? {
        state == .needsSignedBuild ? String(localized: "Needs a signed build") : nil
    }
}

extension EnvironmentValues {
    /// Why the privileged helper cannot run here; nil when it might.
    @Entry var coreographyHelperUnavailable: String? = nil
}
