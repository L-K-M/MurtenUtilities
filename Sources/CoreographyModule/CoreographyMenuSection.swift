import AppKit
import SwiftUI
import Charts
import CoreographyServices

/// Coreography's part of the suite's menu-bar companion, which replaces its
/// own menu-bar extra: mini lanes from the window's own model, the top
/// offender and a way into the pane. Sampling runs while it shows.
@MainActor
struct CoreographyMenuSection: View {
    let session: CoreographySession
    /// Opens Coreography's pane in the suite window.
    let openPane: @MainActor () -> Void

    var body: some View {
        let model = session.model
        let hud = session.hud
        let capacity = Double(model.latest?.inventory.physicalMemoryBytes ?? 0)
        VStack(alignment: .leading, spacing: 8) {
            MiniLane(
                title: String(localized: "CPU"), value: MetricText.percent(model.reading(for: .cpu)?.numericValue),
                points: model.points(for: .cpu), maximum: MetricText.percentScale, color: .blue
            )
            MiniLane(
                title: String(localized: "Memory"), value: MetricText.bytes(model.reading(for: .memory)?.numericValue),
                points: model.points(for: .memory), maximum: capacity > 0 ? capacity : nil, color: .teal
            )
            MiniLane(
                title: String(localized: "Network"),
                value: "↓" + MetricText.rate(model.reading(for: .networkReceived)?.numericValue)
                    + " ↑" + MetricText.rate(model.reading(for: .networkSent)?.numericValue),
                points: model.points(for: .networkReceived), secondary: model.points(for: .networkSent),
                maximum: nil, color: .blue
            )
            MiniLane(
                title: String(localized: "Disk"),
                value: "R " + MetricText.rate(model.reading(for: .diskRead)?.numericValue)
                    + " W " + MetricText.rate(model.reading(for: .diskWritten)?.numericValue),
                points: model.points(for: .diskRead), secondary: model.points(for: .diskWritten),
                maximum: nil, color: .orange
            )
            Text(topOffender(model)).font(.caption).foregroundStyle(.secondary)
            if let recording = model.recordingName {
                HStack {
                    Label("Recording \(recording)", systemImage: "record.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Stop") { Task { await model.stopRecording() } }
                        .help("Stop and save the recording")
                }
            }
            HStack {
                Button(model.samplingPaused ? "Resume" : "Pause") {
                    model.samplingPaused ? model.resumeSampling() : model.pauseSampling()
                }
                .help(model.samplingPaused
                      ? "Resume recording; the pause stays as a labelled gap"
                      : "Pause recording; the pause stays as a labelled gap")
                Button(model.displayMode == .live ? "Hold" : "Live") { model.toggleDisplayHold() }
                    .help(model.displayMode == .live ? "Hold the display" : "Return to live")
                Button(hud.isShown ? "Hide HUD" : "Show HUD") { hud.toggle() }
                Spacer()
                Button("Open System Monitor") { openPane() }
            }
            .controlSize(.small)
        }
        .monospacedDigit()
        .onAppear { session.appeared(.menu) }
        .onDisappear { session.disappeared(.menu) }
    }

    private func topOffender(_ model: DashboardModel) -> String {
        guard let top = model.displayedContributors?.cpu.first else { return String(localized: "Top: collecting…") }
        return String(localized: "Top: \(top.name) \(MetricText.percent(top.value))")
    }
}

/// One compact lane: title, value and the last minute without axes; an
/// optional second series (sent, written) draws fainter.
private struct MiniLane: View {
    private static let visibleSeconds: TimeInterval = 60
    let title: String
    let value: String
    let points: [DashboardPoint]
    var secondary: [DashboardPoint] = []
    /// Fixed scale for percentages and capacity; nil autoscales rates.
    let maximum: Double?
    let color: Color

    var body: some View {
        let end = max(points.last?.time ?? Date(), secondary.last?.time ?? .distantPast)
        let start = end.addingTimeInterval(-Self.visibleSeconds)
        let visible = visiblePoints(points, start, end)
        let faint = visiblePoints(secondary, start, end)
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.caption.weight(.semibold))
            }
            Chart {
                ForEach(visible) { point in
                    LineMark(
                        x: .value("Time", point.time), y: .value(title, point.value),
                        series: .value("Segment", "mini-\(point.segment)")
                    )
                    .foregroundStyle(color)
                }
                ForEach(faint) { point in
                    LineMark(
                        x: .value("Time", point.time), y: .value(title, point.value),
                        series: .value("Segment", "faint-\(point.segment)")
                    )
                    .foregroundStyle(color.opacity(0.45))
                }
            }
            .chartXScale(domain: start...end)
            .chartYScale(domain: 0...max(1, maximum ?? ((visible + faint).map(\.value).max() ?? 1)))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: 28)
            .accessibilityLabel("\(title) \(value)")
        }
    }
}
