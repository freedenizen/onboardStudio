import Foundation

/// One corner on the lap against the same corner on the reference: both readings, and the time
/// lost in each phase.
///
/// The loss is read off the delta trace between the phase's bounds on the reference lap, with
/// one change: the braking phase begins at the earlier of the two brake points, so braking early
/// shows up as time lost in braking rather than leaking into the straight before.
public struct CornerComparison: Sendable, Equatable, Codable {
    public let index: Int
    /// What the circuit calls it ("4", "3a") when the labels are known, else its number.
    public let label: String
    public let lap: CornerMetrics
    public let reference: CornerMetrics
    /// Seconds lost (+) or gained (−) from the braking phase's start to the exit phase's end.
    public let timeLost: Double
    public let phaseLoss: [CornerPhase: Double]
    /// Where on the reference the loss is read, metres: from the earlier brake point to where the
    /// next corner's braking takes over. `nil` for a comparison made by hand.
    public var range: ClosedRange<Double>?
    /// The traffic mark covering the corner on either lap (#571); such a corner is no
    /// opportunity and says nothing about consistency.
    public var traffic: CornerTraffic?
    /// What the telemetry suggests may have been traffic in the corner on the lap (#572), when it
    /// is not marked. Only a suggestion: the corner is coached as any other.
    public var suggestion: TrafficSuggestion?
    /// Where the delta grew the most, if it grew anywhere.
    public var worstPhase: CornerPhase? {
        let worst = CornerPhase.allCases.max { (phaseLoss[$0] ?? 0) < (phaseLoss[$1] ?? 0) }
        return worst.flatMap { (phaseLoss[$0] ?? 0) > 0 ? $0 : nil }
    }

    /// Pairs the two laps' corners by index and reads the losses off `delta`, which is on the
    /// reference's grid. `labels` are the circuit's corner names in corner order, when known.
    public static func compare(
        lap: [CornerMetrics], reference: [CornerMetrics], delta: LapDeltaTrace, labels: [String] = []
    ) -> [CornerComparison] {
        let pairs: [(lap: CornerMetrics, reference: CornerMetrics)] = reference.compactMap { referenceCorner in
            lap.first { $0.index == referenceCorner.index }.map { ($0, referenceCorner) }
        }
        // Each corner's braking begins at the earlier of the two brake points, and the corner
        // before it hands over there, so no stretch of lap is counted twice or not at all.
        var starts = pairs.map { pair -> Double in
            let referenceStart = pair.reference.phaseStart
            guard let lapBrake = pair.lap.brakePointMeters else { return referenceStart }
            return min(referenceStart, pair.reference.corner.apexDistance - lapBrake)
        }
        for index in starts.indices where index > 0 {
            starts[index] = max(starts[index], pairs[index - 1].reference.corner.endDistance)
        }
        return pairs.indices.map { index in
            let pair = pairs[index]
            var bounds = pair.reference.phases
            let start = min(starts[index], bounds[.braking]?.upperBound ?? starts[index])
            if let braking = bounds[.braking] { bounds[.braking] = start...braking.upperBound }
            if let exit = bounds[.exit] {
                let end = index + 1 < starts.count ? max(exit.lowerBound, starts[index + 1]) : exit.upperBound
                bounds[.exit] = exit.lowerBound...end
            }
            var losses: [CornerPhase: Double] = [:]
            for phase in CornerPhase.allCases {
                guard let range = bounds[phase] else { continue }
                losses[phase] = delta.loss(from: range.lowerBound, to: range.upperBound)
            }
            let end = bounds[.exit]?.upperBound ?? pair.reference.phaseEnd
            let cornerIndex = pair.reference.index
            return CornerComparison(
                index: cornerIndex,
                label: cornerIndex < labels.count && !labels[cornerIndex].isEmpty
                    ? labels[cornerIndex] : "\(cornerIndex + 1)",
                lap: pair.lap, reference: pair.reference, timeLost: delta.loss(from: start, to: end), phaseLoss: losses,
                range: start...max(start, end))
        }
    }
}
