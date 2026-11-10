import SwiftUI
import MurtenCore

/// Suite settings plus one tab per module that brings its own.
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            GeneralSettings(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            BackgroundSettings(model: model)
                .tabItem { Label("Background Checks", systemImage: "waveform.path.ecg") }
            ForEach(model.modulesWithSettings) { module in
                if let pane = model.settingsPane(for: module.id) {
                    pane
                        .defaultAppStorage(model.defaults(for: module.id))
                        .tabItem { Label(module.name, systemImage: module.systemImage) }
                }
            }
        }
        .frame(width: 560)
        .padding(20)
    }
}

private struct GeneralSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Keep Murten Utilities in the menu bar", isOn: residentBinding)
                Text("Shows suggestions in the menu bar and lets enabled tools check in the background. Off by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Open at login", isOn: loginBinding)
                    .disabled(model.launchAtLogin == .unsupported)
                if model.launchAtLogin == .requiresApproval {
                    Text("Approve Murten Utilities in System Settings › General › Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Check for Murten Utilities updates", selection: $model.settings.updateChecks) {
                    Text("Never").tag(SuiteSettings.UpdateChecks.off)
                    Text("Daily").tag(SuiteSettings.UpdateChecks.daily)
                }
                Text("Asks GitHub for the latest release. Nothing is downloaded or installed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Check Now") { Task { await model.checkForUpdates() } }
                        .disabled(model.updateCheck == .checking)
                    if let updateStatus {
                        Text(updateStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// The outcome of the last check, so Check Now never ends in silence.
    private var updateStatus: String? {
        switch model.updateCheck {
        case .notChecked: return nil
        case .checking: return "Checking…"
        case .upToDate: return "You have the latest release."
        case .available(let version): return "Version \(version) is available."
        case .failed(let message): return "Could not check for updates: \(message)"
        }
    }

    private var residentBinding: Binding<Bool> {
        Binding(get: { model.settings.residentMode == .on },
                set: { model.settings.residentMode = $0 ? .on : .off })
    }

    private var loginBinding: Binding<Bool> {
        Binding(get: { model.launchAtLogin == .enabled || model.launchAtLogin == .requiresApproval },
                set: { model.setLaunchAtLogin($0 ? .register : .unregister) })
    }
}

private struct BackgroundSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            if model.settings.residentMode == .off {
                // Everything below is disabled; say why and where to change it.
                Section {
                    Text("Background checks run only while Murten Utilities is in the menu bar. Turn that on under General.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Tools") {
                if model.watchedModules.isEmpty {
                    Text("No tool has a background check yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.watchedModules) { module in
                    WatcherRow(model: model, module: module)
                }
                if model.notificationAuthorization == .denied {
                    Text("Notifications are turned off for Murten Utilities in System Settings › Notifications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Pause checks") {
                Toggle("On battery power", isOn: $model.settings.pauseOnBattery)
                Toggle("In Low Power Mode", isOn: $model.settings.pauseInLowPowerMode)
                Toggle("On metered networks (network checks only)", isOn: $model.settings.pauseOnExpensiveNetwork)
                Toggle("During quiet hours", isOn: quietHoursEnabled)
                if let quietHours = model.settings.quietHours {
                    HStack {
                        MinutePicker(title: "From", minute: quietHours.startMinute) {
                            model.settings.quietHours = QuietHours(startMinute: $0, endMinute: quietHours.endMinute)
                        }
                        MinutePicker(title: "to", minute: quietHours.endMinute) {
                            model.settings.quietHours = QuietHours(startMinute: quietHours.startMinute, endMinute: $0)
                        }
                    }
                }
            }
            .disabled(model.settings.residentMode == .off)
        }
        .formStyle(.grouped)
    }

    private var quietHoursEnabled: Binding<Bool> {
        Binding(get: { model.settings.quietHours != nil },
                set: { model.settings.quietHours = $0 ? QuietHours(startMinute: 22 * 60, endMinute: 7 * 60) : nil })
    }
}

private struct WatcherRow: View {
    @Bindable var model: AppModel
    let module: SuiteModule

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label {
                    Text(module.name)
                } icon: {
                    ToolIcon(module: module)
                        .frame(width: 28, height: 28)
                }
                Spacer()
                captionedSwitch("Check", isOn: enabled, describedAs: "Check \(module.name) in the background")
                captionedSwitch("Notify", isOn: notify, describedAs: "Notify about \(module.name)")
            }
            Text(healthText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(model.settings.residentMode == .off)
    }

    /// A switch with its caption directly beside it. A form's own toggle
    /// layout pushes the two apart, so "Notify" read as the caption of the
    /// Check switch. The accessible name says which tool the switch is for.
    private func captionedSwitch(_ title: String, isOn: Binding<Bool>, describedAs label: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .accessibilityHidden(true)
            Toggle(label, isOn: isOn)
                .labelsHidden()
        }
        .padding(.leading, 8)
    }

    private var enabled: Binding<Bool> {
        Binding(get: { !model.settings.disabledWatchers.contains(module.id) },
                set: { isOn in
                    if isOn { model.settings.disabledWatchers.remove(module.id) }
                    else { model.settings.disabledWatchers.insert(module.id) }
                })
    }

    private var notify: Binding<Bool> {
        Binding(get: { model.settings.notifyingModules.contains(module.id) },
                set: { isOn in Task { await model.setNotifications(isOn ? .on : .off, for: module.id) } })
    }

    private var healthText: String {
        // An inapplicable tool never runs its check; "not checked yet" would
        // suggest it is about to.
        if case .inapplicable(let reason)? = model.applicability[module.id] {
            return "Cannot check on this Mac: \(reason)"
        }
        guard let health = model.watchHealth[module.id] else { return "Not checked yet." }
        if let failedAt = health.lastFailureAt, failedAt >= (health.lastSuccessAt ?? .distantPast) {
            return "Last check failed \(failedAt.formatted(.relative(presentation: .named))): \(health.lastFailure?.message ?? "unknown error")"
        }
        if let succeededAt = health.lastSuccessAt {
            return "Last checked \(succeededAt.formatted(.relative(presentation: .named)))."
        }
        return "Not checked yet."
    }
}

/// Picks a time of day as minutes after midnight.
private struct MinutePicker: View {
    let title: String
    let minute: Int
    let onChange: (Int) -> Void

    var body: some View {
        DatePicker(title, selection: binding, displayedComponents: .hourAndMinute)
    }

    private var binding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                onChange((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            })
    }
}
