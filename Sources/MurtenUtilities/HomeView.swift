import SwiftUI
import MurtenCore

/// The suite's front door: one tile per module, Norton-style. Modules not yet
/// migrated show a quiet "planned" badge instead of opening a pane — the deep
/// link router and suggestion feed arrive with the first real module.
struct HomeView: View {
    private let modules = ModuleRegistry.all
    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 210), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(modules) { module in
                        ModuleTile(module: module)
                    }
                }
                .padding(20)
            }
            StatusBar(message: "\(modules.count) tools planned — module panes and watchers land one at a time")
                .frame(height: 22)
        }
        .frame(minWidth: 600, idealWidth: 680, minHeight: 400, idealHeight: 480)
    }
}

private struct ModuleTile: View {
    let module: SuiteModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Image(systemName: module.systemImage)
                    .font(.title2)
                Spacer()
                if module.status == .planned {
                    Text("PLANNED")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
            Text(module.name)
                .font(.headline)
            Text(module.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
