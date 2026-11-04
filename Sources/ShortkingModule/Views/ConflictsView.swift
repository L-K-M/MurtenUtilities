import ShortkingKit
import SwiftUI
import ShortkingCore

/// Conflicts, sorted by severity, each with an explanation and an advisory fix.
///
/// Shortking never rebinds anything itself — it tells you what is happening and
/// where to change it.
struct ConflictsView: View {
    @EnvironmentObject private var state: AppState
    @State private var kindFilter: Set<Conflict.Kind> = []

    var body: some View {
        // The scrollable content has to be the *root* of the screen. A plain VStack
        // does not consume the window's top safe-area inset, so with the header as
        // its first child everything was drawn underneath the title bar and toolbar.
        // Hanging the header off `safeAreaInset` puts it below the chrome and lets
        // the list inset itself correctly beneath it.
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    header
                    Divider()
                }
                .background(.bar)
            }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if filtered.isEmpty {
                EmptyStateView(
                    symbol: state.result.conflicts.isEmpty
                        ? "checkmark.seal"
                        : "line.3.horizontal.decrease.circle",
                    title: state.result.conflicts.isEmpty ? "No conflicts found" : "No matches",
                    message: state.result.conflicts.isEmpty
                        ? "Nothing Shortcut Detective can see is fighting over a key combination. Note that "
                            + "event-tap tools bind in their own code, so their shortcuts are only "
                            + "visible through their config files — check Suspects for processes "
                            + "that could still be intercepting keys."
                        : "No conflicts of the selected kinds."
                )
            } else {
                // A suggestion opens the pane on one conflict; scroll to it once
                // the list (and again once the pane's rescan) has landed.
                ScrollViewReader { proxy in
                    List {
                        ForEach(filtered) { conflict in
                            ConflictListRow(
                                conflict: conflict,
                                isFocused: conflict.combo.groupingKey == state.focusedConflictKey
                            )
                        }
                    }
                    .listStyle(.inset)
                    .onAppear { scrollToFocus(proxy) }
                    .onChange(of: state.result.finishedAt) { scrollToFocus(proxy) }
                    .onChange(of: state.focusedConflictKey) { scrollToFocus(proxy) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ForEach(Conflict.Kind.allCases, id: \.self) { kind in
                    FilterChip(
                        title: "\(kind.displayName) (\(count(of: kind)))",
                        isOn: Binding(
                            get: { kindFilter.contains(kind) },
                            set: { isOn in
                                if isOn { kindFilter.insert(kind) } else { kindFilter.remove(kind) }
                            }
                        )
                    )
                }
                Spacer()
                Button {
                    state.copyExportToPasteboard()
                } label: {
                    Label("Copy report", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
            }

            Text(legend)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if focusedConflictIsGone {
                Label("The conflict the suggestion was about is no longer in the inventory.",
                      systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private var legend: String {
        "Lower dispatch layers win: a shortcut matched inside WindowServer never reaches an app's "
            + "menu bar. Layer numbers are shown on every badge. Acknowledging a conflict between "
            + "apps stops Murten Utilities suggesting it; it stays listed here."
    }

    private var focusedConflictIsGone: Bool {
        guard let key = state.focusedConflictKey, !state.isScanning else { return false }
        return !state.result.conflicts.contains { $0.combo.groupingKey == key }
    }

    private func scrollToFocus(_ proxy: ScrollViewProxy) {
        guard let key = state.focusedConflictKey,
              let target = filtered.first(where: { $0.combo.groupingKey == key }) else { return }
        proxy.scrollTo(target.id, anchor: .top)
    }

    private func count(of kind: Conflict.Kind) -> Int {
        state.result.conflicts.filter { $0.kind == kind }.count
    }

    private var filtered: [Conflict] {
        guard !kindFilter.isEmpty else { return state.result.conflicts }
        return state.result.conflicts.filter { kindFilter.contains($0.kind) }
    }
}

/// A caption plus one chip per claim, each showing the layer, the owner, and the
/// function it binds — the label is what distinguishes two claims by the same owner.
struct ClaimChipRow: View {
    let caption: String
    let claims: [Claim]

    /// A conflict with dozens of claimants is real, but listing them all turns one
    /// row into a screenful. Show enough to recognise the situation and count the
    /// rest; the full list is in the combo's detail pane.
    private static let visibleLimit = 6

    private var visible: [Claim] { Array(claims.prefix(Self.visibleLimit)) }
    private var overflow: Int { max(0, claims.count - Self.visibleLimit) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                FlowingChips(claims: visible)
                if overflow > 0 {
                    Text("and \(overflow) more")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

private struct FlowingChips: View {
    let claims: [Claim]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips }
            VStack(alignment: .leading, spacing: 4) { chips }
        }
    }

    @ViewBuilder
    private var chips: some View {
        ForEach(claims) { claim in
            HStack(spacing: 4) {
                LayerBadge(layer: claim.layer, compact: true)
                Text(claim.ownerName)
                    .font(.caption)
                if let label = claim.label, !label.isEmpty {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct ConflictListRow: View {
    @EnvironmentObject private var state: AppState
    let conflict: Conflict
    /// The conflict a suggestion opened the pane on.
    var isFocused = false

    /// Two claims from the same owner with the same label are one thing to the
    /// user, however many records back them — "macOS, macOS" is noise.
    private var dedupedLosers: [Claim] {
        var seen = Set<String>()
        return conflict.losers.filter { claim in
            seen.insert("\(claim.owner?.identity ?? claim.ownerName)|\(claim.label ?? "")").inserted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                KeyComboBadge(combo: conflict.combo)
                ConflictChip(conflict: conflict)
                Spacer()
                if conflict.isBetweenApps {
                    AcknowledgeControl(conflict: conflict)
                }
                Button("Investigate") {
                    state.investigate(combo: conflict.combo)
                }
                .controlSize(.small)
            }

            Text(conflict.explanation)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                // Long measures are hard to read; conflict explanations are prose,
                // not table cells, so they stop well short of the window edge.
                .frame(maxWidth: 720, alignment: .leading)

            if let suggestion = conflict.suggestion {
                Label(suggestion, systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 720, alignment: .leading)
            }

            if let winner = conflict.winner {
                ClaimChipRow(caption: "Wins:", claims: [winner])
            }

            if !dedupedLosers.isEmpty {
                ClaimChipRow(caption: "Loses:", claims: dedupedLosers)
            }
        }
        .padding(.vertical, 8)
        .listRowBackground(isFocused ? Color.accentColor.opacity(0.12) : nil)
    }
}

/// Stops Murten Utilities suggesting a conflict, or lets it suggest it again.
/// The conflict stays in the inventory either way.
private struct AcknowledgeControl: View {
    @EnvironmentObject private var state: AppState
    let conflict: Conflict

    var body: some View {
        if state.isAcknowledged(conflict) {
            HStack(spacing: 6) {
                Label("Acknowledged", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Undo") { state.setAcknowledged(false, for: conflict) }
                    .controlSize(.small)
                    .accessibilityLabel("Undo acknowledgement")
                    .help("Let Murten Utilities suggest this conflict again.")
            }
        } else {
            Button("Acknowledge") { state.setAcknowledged(true, for: conflict) }
                .controlSize(.small)
                .help("Stop Murten Utilities suggesting this conflict. It comes back if another "
                    + "app claims the shortcut too.")
        }
    }
}
