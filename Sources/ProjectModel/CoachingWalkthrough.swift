import Foundation
import TelemetryKit

/// The steps of a guided debrief (#458): the lap in a sentence, its biggest losses one corner at a
/// time, then the plan made of what the driver chose to try. The Coaching window opens on it; the
/// whole analysis is a click away as All Corners.
public struct CoachingWalkthrough: Hashable, Sendable {
    public enum Step: Hashable, Sendable {
        case lap
        /// A corner, by its index in the analysis.
        case corner(Int)
        case plan
    }

    public let steps: [Step]

    /// The lap, the corners the opportunity cards show — the three biggest losses — and the plan.
    public init(analysis: CoachingAnalysis) {
        self.init(corners: analysis.top.map(\.corner.index))
    }

    public init(corners: [Int]) {
        steps = [.lap] + corners.map(Step.corner) + [.plan]
    }

    /// The corners, in the order they are taken.
    public var corners: [Int] {
        steps.compactMap { step in
            if case .corner(let index) = step { return index }
            return nil
        }
    }

    public func next(after step: Step) -> Step? {
        steps.firstIndex(of: step).flatMap { $0 + 1 < steps.count ? steps[$0 + 1] : nil }
    }

    public func previous(before step: Step) -> Step? {
        steps.firstIndex(of: step).flatMap { $0 > 0 ? steps[$0 - 1] : nil }
    }

    /// Which of the corners `step` is, counting from one, and of how many: "Turn 4 · 1 of 3".
    /// `nil` for the lap and the plan, and for a corner not in the walkthrough.
    public func position(of step: Step) -> (number: Int, count: Int)? {
        guard case .corner(let index) = step, let at = corners.firstIndex(of: index) else { return nil }
        return (at + 1, corners.count)
    }
}
