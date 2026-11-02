import SwiftUI
import ObtainintoshCore

/// The tracked programs: name (opens the repository), installed and latest
/// versions, status, and the row's actions. Sortable by every column but
/// the actions, as in the standalone app.
struct ProgramTable: View {
    let model: ObtainintoshModel
    let onEdit: (TrackedApp) -> Void
    let onRemove: (TrackedApp) -> Void

    @State private var sortOrder = [ProgramComparator(field: .name)]
    @Environment(\.openURL) private var openURL

    var body: some View {
        Table(model.apps.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Name", sortUsing: ProgramComparator(field: .name)) { app in
                nameCell(app)
            }
            .width(min: 160, ideal: 260)

            TableColumn("Current", sortUsing: ProgramComparator(field: .current)) { app in
                Text(app.currentVersion ?? "-")
                    .accessibilityLabel(app.currentVersion.map { "Installed \($0)" } ?? "Not installed")
            }
            .width(min: 70, ideal: 100)

            TableColumn("Latest", sortUsing: ProgramComparator(field: .latest)) { app in
                Text(app.latestVersion ?? "-")
                    .accessibilityLabel(app.latestVersion.map { "Latest \($0)" } ?? "Latest unknown")
            }
            .width(min: 70, ideal: 100)

            TableColumn("Status", sortUsing: ProgramComparator(field: .status)) { app in
                statusCell(ProgramStatus(app))
            }
            .width(min: 110, ideal: 160)

            TableColumn("Actions") { app in
                actionsCell(app)
            }
            .width(min: 90, ideal: 100)
        }
        .overlay {
            if model.isLoaded && model.apps.isEmpty {
                ContentUnavailableView("No Programs Tracked", systemImage: "arrow.down.circle",
                                       description: Text("Click Add Program… to start."))
            }
        }
    }

    // MARK: - Cells

    private func nameCell(_ app: TrackedApp) -> some View {
        Button {
            openRepository(app)
        } label: {
            HStack(spacing: 8) {
                ProgramIcon(app: app)
                Text(app.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .buttonStyle(.plain)
        .help("Open repository")
        .accessibilityLabel("Open \(app.name) repository")
    }

    private func statusCell(_ status: ProgramStatus) -> some View {
        HStack(spacing: 4) {
            if status.isAlert {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            }
            Text(status.label)
                .fontWeight(status == .updateAvailable ? .semibold : .regular)
        }
        .help(status.help ?? "")
        .accessibilityElement(children: .combine)
        .accessibilityHint(status.help ?? "")
    }

    private func actionsCell(_ app: TrackedApp) -> some View {
        let action = ProgramAction(app)
        return HStack(spacing: 6) {
            switch action {
            case .revealDownload:
                iconButton("folder", label: "Show in Finder", help: action.help) { model.revealDownload(id: app.id) }
            case .downloadUpdate:
                iconButton("arrow.down.circle", label: "Download update", help: action.help) {
                    model.download(id: app.id)
                }
            case .download:
                iconButton("arrow.down.circle", label: "Download", help: action.help) { model.download(id: app.id) }
            case .nothing:
                EmptyView()
            }
            iconButton("pencil", label: "Edit", help: "Edit this program's name and URL") { onEdit(app) }
            iconButton("trash", label: "Remove",
                       help: "Delete program from list - if it's installed, it will remain on your system") {
                onRemove(app)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func iconButton(_ symbol: String, label: String, help: String?,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(.borderless)
        .disabled(model.isBusy)
        .help(help ?? label)
        .accessibilityLabel(label)
    }

    /// Only web links open; a stored URL without a scheme is read as https.
    private func openRepository(_ app: TrackedApp) {
        let text = app.sourceURL.contains("://") ? app.sourceURL : "https://" + app.sourceURL
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            model.post("\(app.name)'s repository address cannot be opened.", .error)
            return
        }
        openURL(url)
    }
}
