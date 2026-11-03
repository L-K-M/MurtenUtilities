import Foundation

struct BlackoutAnswerState {
    private enum Phase { case idle, running, completed }
    private var phase: Phase = .idle

    var canReport: Bool { phase == .completed }

    mutating func targetChanged() { phase = .idle }

    mutating func began() { phase = .running }

    mutating func ended() {
        // A target change during the test invalidates that test's answer.
        guard phase == .running else { return }
        phase = .completed
    }
}
