import SwiftUI
import RepoMenCore

/// Pane layout: category sidebar + item table. The suite's window supplies the
/// title and the way back to all tools.
struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 230)
        } detail: {
            DetailView()
        }
    }
}
