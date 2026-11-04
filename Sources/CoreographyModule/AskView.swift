import SwiftUI
import CoreographyServices

/// What leaves the Mac, stated wherever a question can be asked (plan: show
/// the provider and the data-sharing scope).
private let sharingNotice = String(localized: """
    Questions and requested readings (resource use, app and process names, PIDs, sleep history and sleep-preventing assertion types, never executable paths or process arguments) \
    go directly to Anthropic. Calls happen only when you ask.
    """)

/// Ask Coreography: optional, collapsed by default, answered from the same
/// read-only diagnostic tools as MCP.
struct AskPanel: View {
    @Bindable var model: DashboardModel
    @Binding var question: String

    var body: some View {
        DisclosureGroup("Ask System Monitor") {
            VStack(alignment: .leading, spacing: 8) {
                if model.hasProviderKey {
                    HStack {
                        TextField("Why is my Mac slow?", text: $question)
                            .modifier(ReportsTyping(model: model, field: "ask"))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { model.ask(question) }
                        if case .asking = model.askState {
                            Button("Cancel") { model.cancelAsk() }
                        } else {
                            Button("Ask") { model.ask(question) }
                                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    answer
                } else {
                    Text("Add an Anthropic API key in Settings > System Monitor to ask questions in plain language.")
                    SettingsLink { Text("Open Settings…") }
                }
                Text(sharingNotice).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
        .task { await model.refreshProviderKey() }
    }

    @ViewBuilder
    private var answer: some View {
        switch model.askState {
        case .idle:
            EmptyView()
        case .asking:
            ProgressView("Asking…").controlSize(.small)
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        case .answered(let answer):
            Text(answer.text).textSelection(.enabled)
            if !answer.evidence.isEmpty {
                // Plan: links to the processes and time ranges used as evidence.
                HStack {
                    Text("Show:").font(.caption).foregroundStyle(.secondary)
                    ForEach(answer.evidence.prefix(AskText.linkLimit), id: \.self) { evidence in
                        Button(AskText.label(evidence)) { model.follow(evidence) }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
            }
            if !answer.toolCalls.isEmpty {
                Text("Evidence read: " + answer.toolCalls.map { $0.name + $0.arguments + ($0.failed ? " (failed)" : "") }
                    .joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text("Snapshot \(answer.snapshotID.uuidString.prefix(8)); later readings are not included.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private enum AskText {
    /// Links that fit one line of the panel; the first cited come first.
    static let linkLimit = 6

    /// Examples: "PID 42", "Safari", "14:02:10–14:12:10"; a range across
    /// midnight names both days.
    static func label(_ evidence: AskEvidence) -> String {
        switch evidence {
        case .process(let pid): return String(localized: "PID \(pid.formatted(.number.grouping(.never)))")
        case .app(let name): return name
        case .range(let range):
            let sameDay = Calendar.current.isDate(range.lowerBound, inSameDayAs: range.upperBound)
            let style = Date.FormatStyle(date: sameDay ? .omitted : .abbreviated, time: .standard)
            return range.lowerBound.formatted(style) + "–" + range.upperBound.formatted(style)
        }
    }
}

/// Coreography's tab in the suite's Settings; the provider key lives only
/// in the Keychain. The standalone app's Updates, Menu bar, Dock and
/// Briefing widget sections have no counterpart here: the suite owns its
/// update check, menu-bar item and Dock icon, and there are no widgets.
struct SettingsView: View {
    @Bindable var model: DashboardModel
    let mcpAccess: MCPAccess
    @Bindable var hud: HUDController
    let helperAccess: HelperAccess
    @State private var key = ""
    @State private var message: String?
    @State private var confirmingDelete = false
    @AppStorage(InteractionFeedback.settingKey) private var braidSounds = InteractionFeedback.enabledByDefault

    var body: some View {
        Form {
            Section("History") {
                Picker("Keep", selection: $model.historyRetention) {
                    ForEach(HistoryRetention.allCases) { preset in
                        Text(RetentionText.label(preset)).tag(preset)
                    }
                }
                .disabled(!model.recordsHistory)
                Text(RetentionText.size(model.historyBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.recordsHistory
                     ? "History stays on this Mac, excluded from backups. Local snapshots and administrators can still read it."
                     : "History is not being recorded" + (model.historyProblem.map { ": \($0)" } ?? "."))
                    .font(.caption)
                if let problem = model.historyProblem, model.recordsHistory {
                    Text("Last write failed: \(problem)").font(.caption).foregroundStyle(.red)
                }
                // Deleting cannot be undone, so one click only asks.
                Button("Delete history…", role: .destructive) { confirmingDelete = true }
                    .disabled(!model.recordsHistory)
                    .confirmationDialog("Delete all recorded history?", isPresented: $confirmingDelete) {
                        Button("Delete history", role: .destructive) {
                            Task {
                                message = await model.deleteHistory() ?? String(localized: "History deleted.")
                                await model.refreshHistorySize()
                            }
                        }
                    } message: {
                        Text("Every stored sample, app total and day summary is removed from this Mac. This cannot be undone.")
                    }
            }
            MCPAccessSection(access: mcpAccess)
            HelperSection(access: helperAccess)
            Section("Alerts") {
                ForEach(model.alertRules) { rule in
                    Picker(rule.title, selection: Binding(
                        get: { model.alertShortcuts[rule.id] ?? "" },
                        set: { model.setShortcut($0, for: rule.id) }
                    )) {
                        Text("No Shortcut").tag("")
                        // A saved Shortcut stays listed even if it has since been renamed or deleted.
                        let names = Array(Set((model.availableShortcuts ?? []) + [model.alertShortcuts[rule.id]].compactMap { $0 })).sorted()
                        ForEach(names, id: \.self) { Text($0).tag($0) }
                    }
                }
                Text(model.shortcutsUnlisted
                     ? "Shortcuts could not be listed; rules still tint their lane."
                     : "A rule runs its Shortcut when it is raised, at most once every 15 minutes.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Rules are checked while System Monitor samples: while its pane or menu section shows, the HUD is up, or a recording runs. Suggestions and notifications come from Murten Utilities' background check instead.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Your alert rules") {
                ForEach($model.customAlertRules) { $rule in
                    CustomAlertEditor(rule: $rule) { model.customAlertRules.removeAll { $0.id == rule.id } }
                }
                Button("Add rule") { model.customAlertRules.append(.starter) }
                    .disabled(model.customAlertRules.count >= CustomAlertRule.maximumCount)
                Text("A rule tints its lane and marks the timeline once the reading stays past its threshold, and clears once it stays back past the clear value. It reads what history records: the primary interface, and the storage device and GPU when there is only one.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Processes") {
                Picker("CPU per process", selection: $model.processCPUScale) {
                    Text("Share of the whole machine").tag(ProcessCPUScale.machine)
                    Text("One core = 100 %").tag(ProcessCPUScale.oneCore)
                }
                Text("Lanes always show the whole machine; the table, inspector and cpu: filters follow this choice.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Lanes") {
                ForEach(model.laneLayout.order) { lane in
                    Toggle(LaneText.title(lane), isOn: Binding(
                        get: { !model.laneLayout.hidden.contains(lane) },
                        set: { model.laneLayout.set(lane, $0 ? .shown : .hidden) }
                    ))
                    .disabled(model.laneLayout.visible == [lane])
                }
                Button("Restore default lanes") { model.laneLayout = .standard }
                    .disabled(model.laneLayout == .standard)
                Text("Each lane's menu moves, resizes or hides it.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Sounds when the CPU braid opens, folds or catches an app", isOn: $braidSounds)
                Text("Only for your own gestures, and only while macOS plays interface sound effects.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("HUD") {
                Picker("Shows", selection: $hud.settings.density) {
                    Text("One value").tag(HUDDensity.single)
                    Text("One line").tag(HUDDensity.line)
                    Text("Block").tag(HUDDensity.block)
                    Text("Everything").tag(HUDDensity.detailed)
                }
                Picker("Corner", selection: $hud.settings.corner) {
                    Text("Top left").tag(HUDCorner.topLeft)
                    Text("Top right").tag(HUDCorner.topRight)
                    Text("Bottom left").tag(HUDCorner.bottomLeft)
                    Text("Bottom right").tag(HUDCorner.bottomRight)
                }
                Slider(value: $hud.settings.opacity, in: HUDSettings.opacityRange) { Text("Opacity") }
                Slider(value: $hud.settings.textScale, in: HUDSettings.textScaleRange) { Text("Text size") }
                Toggle("Dark backing behind text", isOn: $hud.settings.scrim)
                Toggle("Let clicks pass through", isOn: $hud.settings.clickThrough)
                Text("Turn click-through off to drag the HUD; it remembers where you put it on each display. With System Monitor's pane in front, Control-Command-H shows it and Control-Command-J changes what it shows; the menu section shows it too. Frame rate needs macOS 27.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Data sources") {
                ForEach(model.dataSources, id: \.metric) { source in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(source.metric): \(source.availability.rawValue)")
                        if let detail = source.reason ?? source.source.map({ [$0.provider, $0.driver, $0.channel].compactMap { $0 }.joined(separator: " · ") }),
                           !detail.isEmpty {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Ask System Monitor") {
                SecureField("Anthropic API key", text: $key)
                HStack {
                    Button("Save key") {
                        Task {
                            message = await model.saveProviderKey(key) ?? String(localized: "Key saved in the Keychain.")
                            key = ""
                        }
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Remove key", role: .destructive) {
                        Task { message = await model.removeProviderKey() ?? String(localized: "Key removed.") }
                    }
                    .disabled(!model.hasProviderKey)
                }
                Text(model.hasProviderKey ? "A key is stored. Model: Claude Opus 5.5." : "No key is stored.")
                    .font(.caption)
                if let message { Text(message).font(.caption) }
                Text(sharingNotice).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 480, idealHeight: 640)
        .task {
            await model.refreshShortcuts()
            await model.refreshProviderKey()
            await model.refreshHistorySize()
        }
    }
}

/// One of the person's rules: what it watches, when it raises and clears.
/// The standalone app could also notify; the suite's notifications come
/// only from its background check.
private struct CustomAlertEditor: View {
    @Binding var rule: CustomAlertRule
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Watch", selection: $rule.metric) {
                    ForEach(AlertMetric.allCases) { metric in Text(verbatim: metric.name).tag(metric) }
                }
                Picker("Direction", selection: $rule.direction) {
                    Text("above").tag(CustomAlertRule.Direction.above)
                    Text("below").tag(CustomAlertRule.Direction.below)
                }
                .labelsHidden()
                .frame(width: 90)
            }
            HStack {
                TextField("Raise past", value: $rule.threshold, format: .number)
                Text(verbatim: rule.metric.unit)
                TextField("for", value: $rule.raiseAfter, format: .number)
                Text("s")
            }
            HStack {
                TextField("Clear past", value: $rule.clearThreshold, format: .number)
                Text(verbatim: rule.metric.unit)
                TextField("for", value: $rule.clearAfter, format: .number)
                Text("s")
            }
            HStack {
                Spacer()
                Button("Delete", role: .destructive, action: delete)
            }
        }
    }
}

private enum RetentionText {
    static func label(_ preset: HistoryRetention) -> String {
        let cost = ByteCountFormatter.string(fromByteCount: preset.estimatedBytes, countStyle: .file)
        return String(localized: "\(preset.detailedHours) h detailed, \(preset.summaryDays) days summarised, \(preset.monthDays) days by minute (about \(cost))")
    }

    static func size(_ bytes: Int64?) -> String {
        guard let bytes else { return String(localized: "Stored size unknown") }
        let used = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        let cap = ByteCountFormatter.string(fromByteCount: HistoryRetention.sizeCap, countStyle: .file)
        // Live pages only: freed pages and the write-ahead log can make the file itself larger.
        return String(localized: "Now \(used) of history; never more than \(cap)")
    }
}
