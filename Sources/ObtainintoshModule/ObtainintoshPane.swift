import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MurtenCore
import MurtenModuleKit
import ObtainintoshCore

/// Obtainintosh's window as a suite pane: the toolbar, the program table
/// and the dialogs, with every action the standalone app's window had.
/// Opening it checks quietly the first time each session and whenever a
/// suggestion opens it; it never downloads on its own.
struct ObtainintoshPane: View {
    let model: ObtainintoshModel
    let route: ModuleRoute?

    private enum Sheet: Identifiable {
        case add
        case edit(TrackedApp, accessToken: String?)
        case settings

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let app, _): return "edit-\(app.id)"
            case .settings: return "settings"
            }
        }
    }

    @State private var sheet: Sheet?
    @State private var removal: TrackedApp?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let count = model.standaloneOffer {
                StandaloneImportBanner(count: count,
                                       onImport: { Task { await model.importStandaloneList() } },
                                       onDecline: { model.declineStandaloneImport() })
                Divider()
            }
            if let banner = model.errorBanner {
                errorBanner(banner)
                Divider()
            }
            ProgramTable(model: model, onEdit: edit, onRemove: { removal = $0 })
                .disabled(model.isBusy)
        }
        .overlay(alignment: .bottomTrailing) { NoticeStack(model: model) }
        .overlay { ProgressPanel(model: model) }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .add:
                ProgramEditor(model: model, editing: nil, accessToken: nil)
            case .edit(let app, let accessToken):
                ProgramEditor(model: model, editing: app, accessToken: accessToken)
            case .settings:
                ObtainintoshSettingsView(model: model, presentation: .sheet)
            }
        }
        .confirmationDialog(removalQuestion, isPresented: removalIsPresented, presenting: removal) { app in
            Button("Remove", role: .destructive) { Task { await model.remove(id: app.id) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("If it is installed, it remains on your Mac.")
        }
        .task(id: route) { model.paneAppeared(route: route?.action) }
        .moduleCommands(commands)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button("Add Program…") { sheet = .add }
            Button(model.isChecking ? "Checking…" : "Check All") { Task { await model.checkForUpdates() } }
            Button("Import…") { importList() }
            Button("Export…") { exportList() }
                .disabled(model.apps.isEmpty)
            Spacer()
            Button("Settings") { sheet = .settings }
        }
        .disabled(model.isBusy)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                model.errorBanner = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
        }
        .padding(10)
    }

    private var commands: [ModuleCommand] {
        // A shortcut must not replace a sheet or the removal question.
        let idle = !model.isBusy && sheet == nil && removal == nil
        return [
            ModuleCommand("Add Program…", shortcut: KeyboardShortcut("n"), isEnabled: idle) { sheet = .add },
            ModuleCommand("Check All", shortcut: KeyboardShortcut("r"), isEnabled: idle) {
                Task { await model.checkForUpdates() }
            },
            ModuleCommand("Import Program List…", shortcut: KeyboardShortcut("i"), isEnabled: idle) { importList() },
            ModuleCommand("Export Program List…", shortcut: KeyboardShortcut("e"),
                          isEnabled: idle && !model.apps.isEmpty) { exportList() },
            ModuleCommand("Import from the Obtainintosh App…", isEnabled: idle && model.standaloneListExists) {
                Task { await model.importStandaloneList() }
            },
            ModuleCommand("Obtainintosh Settings…", isEnabled: idle) { sheet = .settings },
        ]
    }

    // MARK: - Actions

    private func edit(_ app: TrackedApp) {
        Task {
            let accessToken = await model.accessToken(for: app)
            sheet = .edit(app, accessToken: accessToken)
        }
    }

    private var removalQuestion: String {
        "Are you sure you want to remove \(removal?.name ?? "this program")?"
    }

    private var removalIsPresented: Binding<Bool> {
        Binding(get: { removal != nil }, set: { if !$0 { removal = nil } })
    }

    private static var listType: UTType {
        UTType(filenameExtension: AppList.fileExtension) ?? .json
    }

    private func exportList() {
        guard let contents = model.exportContents() else { return }
        let panel = NSSavePanel()
        panel.title = "Export Program List"
        panel.nameFieldStringValue = AppList.suggestedFileName(for: Date())
        panel.allowedContentTypes = [Self.listType]
        panel.allowsOtherFileTypes = true
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.writeExport(contents, to: url)
    }

    private func importList() {
        let panel = NSOpenPanel()
        panel.title = "Import Program List"
        panel.allowedContentTypes = [Self.listType, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.importList(from: url) }
    }
}
