import Foundation
import ShortkingCore

enum DifferentialObservations {
    enum Direction: Equatable { case launch, termination }

    struct Transition {
        var owner: Owner
        var direction: Direction
        var at: Date
    }

    static func build(
        candidates: [Transition],
        freed: Set<KeyCombo>,
        newlyClaimed: Set<KeyCombo>
    ) -> [AttributionObservation] {
        return candidates.flatMap { candidate in
            let combos: Set<KeyCombo>
            let kind: AttributionObservation.Kind
            switch candidate.direction {
            case .launch:
                combos = newlyClaimed
                kind = .claimedOnLaunch
            case .termination:
                combos = freed
                kind = .freedOnQuit
            }

            let ambiguous = Set(candidates.lazy
                .filter { $0.direction == candidate.direction }
                .map(\.owner.identity)).count > 1

            return combos.map {
                AttributionObservation(comboKey: $0.groupingKey,
                    ownerIdentity: candidate.owner.identity, ownerName: candidate.owner.name,
                    kind: kind, ambiguous: ambiguous)
            }
        }
    }
}
