import SwiftUI
import AppKit
import DoctorCore
import MurtenCore
import MurtenModuleKit

private enum DoctorStyle {
    static let accent = Color.teal
    static let warning = Color.orange
    static let border = Color.primary.opacity(0.08)
}

struct MainView: View {
    @EnvironmentObject private var doctor: DoctorStore
    @Environment(\.openWindow) private var openWindow
    @State private var showsAddApps = false
    @State private var showsResetAll = false
    /// The suggestion or tile click that opened the pane.
    let route: ModuleRoute?

    init(route: ModuleRoute?) {
        self.route = route
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Label("Watch list", systemImage: "stethoscope")
                        .font(.headline)
                    Spacer()
                    Text("\(doctor.apps.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if doctor.apps.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "app.badge.checkmark")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(DoctorStyle.accent)
                        Text("Watch the apps you rely on")
                            .font(.headline)
                        Text("Add apps that need device control or input access.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Add Apps…") { showsAddApps = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(22)
                    .frame(maxHeight: .infinity)
                } else {
                    List(selection: $doctor.selectedID) {
                        ForEach(doctor.apps) { app in
                            WatchListRow(app: app)
                                .tag(app.id)
                                .contextMenu {
                                    Button("Check permissions") { doctor.refresh(appID: app.id) }
                                        .disabled(doctor.isChecking || doctor.isRepairing)
                                    Button("Show in Finder") { doctor.revealApp(app) }
                                    Divider()
                                    Button("Remove from watch list", role: .destructive) { doctor.removeApp(app.id) }
                                        .disabled(doctor.isRepairing)
                                }
                        }
                    }
                    .listStyle(.sidebar)
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle().fill(doctor.monitorEnabled ? DoctorStyle.accent : .secondary).frame(width: 6, height: 6)
                        Text(doctor.monitorEnabled ? "Checking every minute" : "Manual checks")
                            .font(.caption)
                    }
                    if let checked = doctor.lastChecked {
                        Text("Last checked \(checked.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("All apps").font(.headline)
                    Text("Clear device-control, input-monitoring, and Screen & System Audio Recording decisions for every app, not just your watch list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Reset All Permissions…", role: .destructive) { showsResetAll = true }
                        .disabled(doctor.isChecking || doctor.isRepairing)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            VStack(spacing: 0) {
                if let notice = doctor.notice {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle.fill").foregroundStyle(DoctorStyle.accent)
                        Text(notice).font(.callout).textSelection(.enabled)
                        Spacer(minLength: 10)
                        Button { doctor.notice = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Dismiss notice")
                    }
                    .padding(14)
                    .background(DoctorStyle.accent.opacity(0.09))
                    Divider()
                }
                if let app = doctor.selectedApp {
                    AppDetailView(app: app)
                        .id(app.id)
                } else {
                    welcomeView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showsAddApps = true } label: { Label("Add Apps", systemImage: "plus") }
                    .help("Choose apps or import existing permission entries")
                    .disabled(doctor.isRepairing)
                Button { doctor.refresh() } label: {
                    if doctor.isChecking {
                        ProgressView().controlSize(.small).frame(width: 16, height: 16)
                    } else {
                        Label("Check", systemImage: "arrow.clockwise")
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(doctor.isChecking || doctor.isRepairing || doctor.apps.isEmpty)
                Button { openWindow(module: .testPad) } label: { Label("Test Pad", systemImage: "text.cursor") }
                    .help("Test an app against a controlled text field")
                Button { doctor.exportReport() } label: { Label("Export Report", systemImage: "square.and.arrow.up") }
                    .disabled(doctor.apps.isEmpty || doctor.isRepairing)
            }
        }
        .sheet(isPresented: $showsAddApps) { AddAppsView() }
        .sheet(isPresented: $showsResetAll) { ResetAllView() }
        .tint(DoctorStyle.accent)
        .frame(minWidth: 980, minHeight: 650)
        // The standalone app's File-menu commands, in the suite's Tool menu.
        .moduleCommands([
            ModuleCommand("Add Applications…", shortcut: KeyboardShortcut("o")) { doctor.chooseApps() },
            ModuleCommand("Refresh Permissions", shortcut: KeyboardShortcut("r"),
                          isEnabled: !(doctor.isChecking || doctor.isRepairing)) { doctor.refresh() },
            ModuleCommand("Export Diagnostic Report…", shortcut: KeyboardShortcut("e", modifiers: [.command, .shift])) {
                doctor.exportReport()
            }
        ])
        .onAppear { doctor.apply(route) }
        // Checks while the pane is visible; cancelled when it goes away.
        .task { await doctor.monitorWhileVisible() }
    }

    private var welcomeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "stethoscope")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(DoctorStyle.accent)
                VStack(alignment: .leading, spacing: 9) {
                    Text("A clearer picture of app access")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("Check what macOS reports, test what an app can do, and repair only the permission that needs attention.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Button("Find Apps with Permission Records…") { showsAddApps = true }
                        .buttonStyle(.borderedProminent)
                    Button("Choose Apps…") { doctor.chooseApps() }
                }
                DoctorCard {
                    VStack(alignment: .leading, spacing: 18) {
                        welcomeStep("1", "Build your watch list", "Select apps you expect to have access, including their relevant helpers.")
                        welcomeStep("2", "Compare records and behavior", "A recorded grant is evidence of authorization. The Test Pad records a separate, manual functional test.")
                        welcomeStep("3", "Repair with a precise scope", "Reset an individual app and permission, approve access again in System Settings, then test the result.")
                    }
                }
                capabilityFooter
            }
            .padding(36)
            .frame(maxWidth: 800, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var capabilityFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Permission queries depend on your macOS version and device configuration.", systemImage: "info.circle")
            if !doctor.capabilityDetail.isEmpty { Text(doctor.capabilityDetail) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }

    private func welcomeStep(_ number: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.headline.monospacedDigit())
                .foregroundStyle(DoctorStyle.accent)
                .frame(width: 28, height: 28)
                .background(DoctorStyle.accent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct WatchListRow: View {
    let app: WatchedApp
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable().interpolation(.high).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.body.weight(.medium)).lineLimit(1)
                Text(app.summary).font(.caption).foregroundStyle(summaryColor(app)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

private struct AppDetailView: View {
    @EnvironmentObject private var doctor: DoctorStore
    @Environment(\.openWindow) private var openWindow
    let app: WatchedApp
    @State private var showsRepair = false
    @State private var showsRestart = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if doctor.queryAvailable == false {
                    Label {
                        Text("Permission queries are unavailable. You can still inspect the app identity, use the Test Pad, and open System Settings. \(doctor.capabilityDetail)")
                    } icon: { Image(systemName: "exclamationmark.triangle") }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .background(DoctorStyle.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                }
                DoctorCard {
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Label("Authorization reported by macOS", systemImage: "checkmark.shield")
                                .font(.headline)
                            Spacer()
                            Text("EXPECT ACCESS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        }
                        ForEach(PermissionService.allCases) { service in
                            PermissionRow(app: app, service: service)
                            if service != PermissionService.allCases.last { Divider() }
                        }
                        Text("A grant does not prove that the running app works. Select only the permissions this app actually needs.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                functionalEvidence
                identityCard
                if !recentEvents.isEmpty { historyCard }
            }
            .padding(26)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .sheet(isPresented: $showsRepair) { RepairView(app: app) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable().interpolation(.high).frame(width: 62, height: 62)
            VStack(alignment: .leading, spacing: 7) {
                Text(app.name).font(.system(size: 27, weight: .semibold, design: .rounded))
                HStack(spacing: 9) {
                    Text(app.version.isEmpty ? "Version unknown" : "Version \(app.version)")
                    Text("·")
                    Text(doctor.isRunning(app) ? "Running" : "Not running")
                }
                .font(.callout).foregroundStyle(.secondary)
                StatusPill(title: app.summary, color: summaryColor(app))
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 8) {
                Button("Repair…") { showsRepair = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(doctor.isChecking || doctor.isRepairing || !app.canReset)
                    .help(app.canReset ? "Review the exact scope before resetting permission" : "Path-based clients must be managed in System Settings")
                Button("Open Settings") { doctor.openSettings(.accessibility) }
            }
        }
    }

    private var functionalEvidence: some View {
        DoctorCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label("Functional evidence", systemImage: "text.badge.checkmark").font(.headline)
                    Spacer()
                    Button("Open Test Pad") { doctor.selectedID = app.id; openWindow(module: .testPad) }
                }
                if let test = app.functionalTest {
                    HStack(spacing: 9) {
                        StatusPill(title: outcomeTitle(test.outcome), color: outcomeColor(test.outcome))
                        Text("Manually recorded \(test.recordedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !test.note.isEmpty { Text(test.note).font(.callout).textSelection(.enabled) }
                    Text("Tested version \(test.appVersion.isEmpty ? "unknown" : test.appVersion). A result applies only to the capability you tested.")
                        .font(.caption).foregroundStyle(.secondary)
                    if test.appPath != app.path || test.appVersion != app.version {
                        Label("The app has changed since this test. Test the current copy again.", systemImage: "clock.badge.exclamationmark")
                            .font(.caption).foregroundStyle(DoctorStyle.warning)
                    }
                } else {
                    Text("No functional test recorded")
                        .font(.callout.weight(.medium))
                    Text("Use this app to type into or act on the Test Pad. Record what happened separately from the permission result.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let working = app.lastKnownWorking {
                    Text("Last confirmed working: \(working.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var identityCard: some View {
        DoctorCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    identityLine("Application", app.path)
                    identityLine(app.canReset ? "Bundle ID" : "Path-based client", app.bundleID)
                    identityLine("Signing ID", app.identity.signingIdentifier.isEmpty ? "Unavailable" : app.identity.signingIdentifier)
                    identityLine("Team ID", app.identity.teamIdentifier.isEmpty ? "Unavailable / ad hoc" : app.identity.teamIdentifier)
                    identityLine("Signature", app.identity.signatureDetail)
                    if !app.identity.requirement.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Designated requirement").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            Text(app.identity.requirement).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                    if let changed = app.identityChangedAt {
                        Label("Identity change detected \(changed.formatted(date: .abbreviated, time: .shortened)). Review the current app copy.", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(DoctorStyle.warning)
                    }
                    let paths = doctor.runningPaths(app)
                    if paths.count > 1 || (paths.count == 1 && paths.first != app.path) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Other running copies share this bundle identifier", systemImage: "square.on.square")
                                .font(.caption.weight(.medium)).foregroundStyle(DoctorStyle.warning)
                            ForEach(paths, id: \.self) { Text($0).font(.caption.monospaced()).textSelection(.enabled) }
                        }
                    }
                    if !app.canReset {
                        Text("This permission record identifies an executable by path. Manage its access in System Settings; a bundle-ID reset would target a different identity.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Show in Finder") { doctor.revealApp(app) }
                        Button("Open App") { doctor.openApp(app) }
                            .disabled(doctor.isRepairing)
                        Button("Restart…") { showsRestart = true }
                            .disabled(doctor.isChecking || doctor.isRepairing)
                            .confirmationDialog("Restart \(app.name) without resetting permissions?", isPresented: $showsRestart) {
                                Button("Restart App") { doctor.restartApp(app) }
                            } message: {
                                Text("App Permission Checkup will request a normal quit and reopen this app. Finish any work first, then use the Test Pad to check whether restarting helped.")
                            }
                        Spacer()
                        Button("Check Again") { doctor.refresh(appID: app.id) }
                            .disabled(doctor.isChecking || doctor.isRepairing)
                    }
                }
                .padding(.top, 14)
            } label: {
                HStack {
                    Label("App identity", systemImage: "person.text.rectangle").font(.headline)
                    Spacer()
                    if let valid = app.identity.signatureValid {
                        StatusPill(title: valid ? "Signature valid" : "Review signature", color: valid ? DoctorStyle.accent : DoctorStyle.warning)
                    }
                }
            }
        }
    }

    private var recentEvents: [DoctorEvent] {
        Array(doctor.events.filter { $0.appID == app.id }.sorted { $0.date > $1.date }.prefix(8))
    }

    private var historyCard: some View {
        DoctorCard {
            VStack(alignment: .leading, spacing: 13) {
                Label("Recent activity", systemImage: "clock.arrow.circlepath").font(.headline)
                ForEach(recentEvents) { event in
                    HStack(alignment: .top, spacing: 14) {
                        Text(event.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
                        Text(event.message).font(.callout).textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func identityLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            Text(value).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PermissionRow: View {
    @EnvironmentObject private var doctor: DoctorStore
    let app: WatchedApp
    let service: PermissionService
    private var reading: PermissionReading? { app.readings.first { $0.service == service } }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: serviceSymbol(service))
                .font(.title3).foregroundStyle(DoctorStyle.accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(service.title).font(.callout.weight(.semibold))
                Text(service.explanation).font(.caption).foregroundStyle(.secondary)
                if let reading, reading.result.state == .unknown || reading.result.state == .unavailable {
                    Text(reading.result.detail).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(3).textSelection(.enabled)
                }
            }
            Spacer(minLength: 6)
            StatusPill(title: reading?.result.state.title ?? "Not checked", color: stateColor(reading?.result.state))
                .help(reading?.result.detail ?? "Run a permission check to read the OS-reported authorization.")
            Button { doctor.openSettings(service) } label: { Image(systemName: "arrow.up.right.square") }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(service.title) settings")
                .help("Open \(service.title) in System Settings")
            Toggle("Expect \(service.title) access", isOn: Binding(
                get: { app.expectedServices.contains(service) },
                set: { doctor.setExpected(service, enabled: $0, appID: app.id) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(doctor.isRepairing)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
    }
}

private struct AddAppsView: View {
    @EnvironmentObject private var doctor: DoctorStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selected = Set<UUID>()
    private var filtered: [WatchedApp] {
        doctor.candidates.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search) }
    }
    private func isWatched(_ app: WatchedApp) -> Bool {
        doctor.apps.contains { $0.bundleID == app.bundleID && $0.path == app.path }
    }
    private func hasRecord(_ app: WatchedApp) -> Bool { doctor.recordedClients.contains(app.bundleID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Add apps to your watch list").font(.title2.weight(.semibold))
                    Text("Permission records help you find candidates. Choose the apps you expect to have access.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if doctor.isDiscovering { ProgressView().controlSize(.small) }
            }
            HStack {
                TextField("Search apps or identifiers", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search available apps")
                Button("Select Recorded Apps") {
                    selected.formUnion(doctor.candidates.filter { hasRecord($0) && !isWatched($0) }.map(\.id))
                }
                .disabled(doctor.isDiscovering)
            }
            List {
                ForEach(filtered) { app in
                    HStack(spacing: 10) {
                        Toggle("Select \(app.name)", isOn: Binding(
                            get: { selected.contains(app.id) },
                            set: { if $0 { selected.insert(app.id) } else { selected.remove(app.id) } }
                        ))
                        .labelsHidden().toggleStyle(.checkbox).disabled(isWatched(app))
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                            .resizable().frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name).font(.callout.weight(.medium))
                            Text(app.bundleID).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if isWatched(app) {
                            Text("Watching").font(.caption).foregroundStyle(.secondary)
                        } else if hasRecord(app) {
                            StatusPill(title: "Permission record", color: DoctorStyle.accent)
                        }
                    }
                    .padding(.vertical, 3)
                    .help(app.path)
                }
                if filtered.isEmpty && !doctor.isDiscovering {
                    Text(search.isEmpty ? "No apps found. Choose an application directly." : "No apps match your search.")
                        .foregroundStyle(.secondary).padding()
                }
            }
            .listStyle(.inset)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DoctorStyle.border))
            if doctor.queryAvailable == false {
                Text("Permission records are unavailable on this configuration. You can still add installed apps and use manual tests.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Choose Apps…") { doctor.chooseApps(); dismiss() }
                Button("Refresh List") { selected.removeAll(); doctor.discoverApps() }
                    .disabled(doctor.isDiscovering)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add \(selected.count == 1 ? "App" : "Apps")") {
                    doctor.addApps(doctor.candidates.filter { selected.contains($0.id) && !isWatched($0) })
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty || doctor.isDiscovering)
            }
        }
        .padding(24)
        .frame(width: 710, height: 560)
        .onAppear { doctor.discoverApps() }
        .tint(DoctorStyle.accent)
    }
}

private struct RepairView: View {
    @EnvironmentObject private var doctor: DoctorStore
    @Environment(\.dismiss) private var dismiss
    let app: WatchedApp
    @State private var services: Set<PermissionService>
    @State private var quitFirst = true
    @State private var reopen = true
    @State private var completed = false
    @State private var attempted = false

    init(app: WatchedApp) {
        self.app = app
        _services = State(initialValue: Set(app.expectedServices))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(spacing: 12) {
                Image(systemName: completed ? "checkmark.circle" : "wrench.and.screwdriver")
                    .font(.system(size: 28, weight: .light)).foregroundStyle(DoctorStyle.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(completed ? "Reset completed" : "Reset selected permissions")
                        .font(.title2.weight(.semibold))
                    Text(app.name).font(.headline)
                }
            }
            Text(app.bundleID).font(.caption.monospaced()).textSelection(.enabled)
            Text(app.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if completed {
                Text("Approve access again in System Settings, then use the Test Pad to verify the affected capability. A completed reset does not mean access has been restored.")
                    .font(.callout)
                HStack {
                    Button("Open Device Control Settings") { doctor.openSettings(.accessibility) }
                    if services.contains(.listenEvent) {
                        Button("Input Monitoring") { doctor.openSettings(.listenEvent) }
                    }
                }
            } else {
                Text("This clears the selected approval decisions for this bundle identifier, including other installed copies. You must grant access again in System Settings.")
                    .font(.callout)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(PermissionService.allCases) { service in
                        Toggle(isOn: Binding(
                            get: { services.contains(service) },
                            set: { if $0 { services.insert(service) } else { services.remove(service) } }
                        )) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(service.title).font(.callout.weight(.medium))
                                Text(service.rawValue).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                .disabled(doctor.isRepairing)
                Toggle("Quit this app before resetting", isOn: $quitFirst).toggleStyle(.checkbox).disabled(doctor.isRepairing)
                Toggle("Reopen this app afterwards", isOn: $reopen).toggleStyle(.checkbox).disabled(doctor.isRepairing)
                Text("Quitting is a normal quit request. If the app remains open, the reset will stop so you can finish any work first.")
                    .font(.caption).foregroundStyle(.secondary)
                if attempted, let notice = doctor.notice {
                    Text(notice).font(.callout).foregroundStyle(DoctorStyle.warning).textSelection(.enabled)
                }
            }
            Divider()
            HStack {
                if doctor.isRepairing {
                    ProgressView().controlSize(.small)
                    Text("Applying selected reset…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(completed ? "Done" : "Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(doctor.isRepairing)
                if !completed {
                    Button("Reset Selected Permissions") {
                        attempted = true
                        Task { completed = await doctor.reset(appID: app.id, services: services, quitFirst: quitFirst, reopen: reopen) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(services.isEmpty || doctor.isRepairing || doctor.isChecking || !app.canReset)
                }
            }
        }
        .padding(26)
        .frame(width: 570)
        .interactiveDismissDisabled(doctor.isRepairing)
        .tint(DoctorStyle.accent)
    }
}

struct TestPadView: View {
    @EnvironmentObject private var doctor: DoctorStore
    @State private var testAppID: UUID?
    @State private var capability: PermissionService = .postEvent
    @State private var text = ""
    @State private var note = ""
    @State private var recorded = false
    @FocusState private var padFocused: Bool
    private var selected: WatchedApp? { doctor.apps.first { $0.id == testAppID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Test Pad", systemImage: "text.cursor").font(.title2.weight(.semibold))
                    Text("Test behavior separately from the permission record.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Focus Test Field") { padFocused = true }
            }
            HStack(spacing: 18) {
                Picker("App", selection: $testAppID) {
                    Text("Choose an app").tag(UUID?.none)
                    ForEach(doctor.apps) { app in Text(app.name).tag(Optional(app.id)) }
                }
                Picker("Capability", selection: $capability) {
                    ForEach(PermissionService.allCases) { Text($0.title).tag($0) }
                }
            }
            if let app = selected {
                Text("\(app.path) · Version \(app.version.isEmpty ? "unknown" : app.version)")
                    .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
            DoctorCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to test").font(.headline)
                    Text(instructions).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Use a harmless test string. Mark the result yourself; text in this field is never treated as proof of permission.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .focused($padFocused)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .accessibilityLabel("App Permission Checkup functional test field")
                if text.isEmpty {
                    Text("Click here, then invoke the app you’re testing…")
                        .foregroundStyle(.tertiary).padding(16).allowsHitTesting(false)
                }
            }
            .frame(minHeight: 165, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(padFocused ? DoctorStyle.accent.opacity(0.7) : DoctorStyle.border, lineWidth: padFocused ? 2 : 1))
            HStack {
                TextField("Observation (optional)", text: $note)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Functional test observation")
                Button("Clear Field") { text = ""; padFocused = true }
            }
            HStack(spacing: 10) {
                if recorded { Label("Result recorded", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(DoctorStyle.accent) }
                Spacer()
                Button("Inconclusive") { record(.inconclusive) }
                Button("Failed") { record(.failed) }
                Button("Passed") { record(.passed) }.buttonStyle(.borderedProminent)
            }
            .disabled(selected == nil || doctor.isRepairing || doctor.isChecking)
            Text("Results are manual observations of this app version and the selected capability. A passing text-insertion test does not establish that every device-control feature works.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 700, minHeight: 640)
        .onAppear { testAppID = doctor.selectedID ?? doctor.apps.first?.id }
        .onChange(of: testAppID) { _, _ in recorded = false }
        .onChange(of: doctor.selectedID) { _, value in testAppID = value; recorded = false }
        .onChange(of: capability) { _, _ in recorded = false }
        .tint(DoctorStyle.accent)
    }

    private var instructions: String {
        switch capability {
        case .postEvent:
            return "Focus the test field below. Use PopChar to insert a character, Rocket to expand an emoji, or a Keyboard Maestro macro to type a fixed token. Check whether the expected text arrives."
        case .accessibility:
            return "Use the app’s window-control or UI-control feature on this Test Pad window—for example, a Keyboard Maestro macro that moves this window. Observe the exact action you requested."
        case .listenEvent:
            return "Focus the test field, then use a known app shortcut or input-triggered action that depends on monitoring input. Confirm that the expected action fires; ordinary typing alone does not test monitoring."
        }
    }

    private func record(_ outcome: FunctionalOutcome) {
        guard let id = testAppID else { return }
        let observation = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = "Manual \(capability.title.lowercased()) test" + (observation.isEmpty ? "." : ": \(observation)")
        doctor.recordTest(appID: id, outcome: outcome, note: details)
        recorded = true
    }
}

struct SettingsView: View {
    @EnvironmentObject private var doctor: DoctorStore

    var body: some View {
        Form {
            Section("Monitoring") {
                Toggle("Check permissions every minute while App Permission Checkup is open", isOn: $doctor.monitorEnabled)
                Text("Automatic checks only read authorization records. They never reset permissions, quit another app, or grant access.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Checks while App Permission Checkup is closed are set in the Background Checks tab.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Privacy and scope") {
                Text("The watch list, app identities, permission results, and your test observations are stored locally. Reports are exported only when you choose Export Report.")
                    .font(.callout)
                Text("macOS 27 calls Accessibility “Device Control and Data Access.” Permission-record queries may be unavailable on older or restricted configurations; manual testing remains available.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .tint(DoctorStyle.accent)
    }
}

struct ResetAllView: View {
    @EnvironmentObject private var doctor: DoctorStore

    var body: some View {
        ResetAllContentView(doctor: doctor)
    }
}

private struct DoctorCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DoctorStyle.border))
    }
}

private struct StatusPill: View {
    let title: String
    let color: Color
    var body: some View {
        Text(title).font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.1), in: Capsule())
            .fixedSize()
    }
}

private func summaryColor(_ app: WatchedApp) -> Color {
    if app.hasFailedTest || app.hasDeniedExpectedPermission { return DoctorStyle.warning }
    if app.functionalTest?.outcome == .passed { return DoctorStyle.accent }
    return .secondary
}

private func stateColor(_ state: AuthorizationState?) -> Color {
    switch state {
    case .granted: return DoctorStyle.accent
    case .denied, .limited: return DoctorStyle.warning
    default: return .secondary
    }
}

private func outcomeTitle(_ outcome: FunctionalOutcome) -> String {
    switch outcome {
    case .passed: return "Passed"
    case .failed: return "Failed"
    case .inconclusive: return "Inconclusive"
    }
}

private func outcomeColor(_ outcome: FunctionalOutcome) -> Color {
    switch outcome {
    case .passed: return DoctorStyle.accent
    case .failed: return DoctorStyle.warning
    case .inconclusive: return .secondary
    }
}

private func serviceSymbol(_ service: PermissionService) -> String {
    switch service {
    case .accessibility: return "hand.point.up.left"
    case .postEvent: return "keyboard"
    case .listenEvent: return "waveform"
    }
}
