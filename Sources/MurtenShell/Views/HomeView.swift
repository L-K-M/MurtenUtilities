import AppKit
import SwiftUI
import MurtenCore

/// The suite's front door: what needs attention, then one tile per tool,
/// Norton-style, in a classic inset well over platinum.
struct HomeView: View {
    let model: AppModel
    @FocusState private var focusedTile: String?

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 240), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    banners
                    SuggestionFeed(model: model)
                    tools
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(InsetWell())
            .padding(10)

            StatusBar(message: statusMessage)
                .frame(height: 22)
        }
        .background(PlatinumBackdrop())
        .onAppear {
            // Coming back from a pane returns focus to the tile that opened it.
            focusedTile = model.lastOpenedModuleID
        }
        .task { await model.refreshEnvironment() }
    }

    @ViewBuilder private var banners: some View {
        if let update = model.availableUpdate {
            Banner(systemImage: "arrow.down.circle",
                   message: "Murten Utilities \(update.version) is available.",
                   actionTitle: "View Release") {
                _ = NSWorkspace.shared.open(update.pageURL)
            }
        }
        ForEach(model.diagnostics) { diagnostic in
            Banner(systemImage: "exclamationmark.triangle", message: diagnostic.message,
                   actionTitle: "Dismiss") {
                model.dismissDiagnostic(diagnostic)
            }
        }
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tools")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(model.modules) { module in
                    ModuleTile(module: module, state: tileState(for: module)) {
                        _ = model.open(ModuleRoute(moduleID: module.id))
                    }
                    .focused($focusedTile, equals: module.id)
                }
            }
        }
    }

    private func tileState(for module: SuiteModule) -> ModuleTile.TileState {
        guard model.isMigrated(module.id) else { return .planned }
        if case .inapplicable(let reason)? = model.applicability[module.id] { return .inapplicable(reason) }
        return .available
    }

    private var statusMessage: String {
        // Counts what the grid shows as available, not what was migrated.
        let available = model.modules.filter { model.isAvailable($0.id) }.count
        let tools = "\(available) of \(model.modules.count) tools available"
        guard model.settings.residentMode == .on else { return "\(tools) · background checks off" }
        let count = model.suggestions.count
        return count == 0 ? "\(tools) · nothing needs attention" : "\(tools) · \(count) suggestion\(count == 1 ? "" : "s")"
    }
}

/// One tool: icon, name and one-line job. Planned and inapplicable tools
/// say why they do not open instead of opening a pane that cannot work.
struct ModuleTile: View {
    enum TileState: Equatable {
        case available
        case planned
        case inapplicable(String)
    }

    let module: SuiteModule
    let state: TileState
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    ToolIcon(module: module)
                        .frame(width: 88, height: 88)
                    Spacer()
                    badge
                }
                Text(module.name)
                    .font(.headline)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(state != .available)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(module.name)
        .accessibilityValue(accessibilityState)
        .accessibilityHint(state == .available ? "Opens the tool. \(module.summary)" : caption)
        .accessibilityAddTraits(.isButton)
    }

    private var caption: String {
        if case .inapplicable(let reason) = state { return reason }
        return module.summary
    }

    @ViewBuilder private var badge: some View {
        switch state {
        case .available:
            EmptyView()
        case .planned:
            Tag(text: "PLANNED")
        case .inapplicable:
            Tag(text: "UNAVAILABLE")
        }
    }

    private var accessibilityState: String {
        switch state {
        case .available: return ""
        case .planned: return "Planned"
        case .inapplicable(let reason): return "Unavailable: \(reason)"
        }
    }
}

private struct Tag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .foregroundStyle(.secondary)
    }
}

/// A one-line, non-modal notice with one action.
struct Banner: View {
    let systemImage: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(message)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(actionTitle, action: action)
        }
        .padding(10)
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
    }
}
