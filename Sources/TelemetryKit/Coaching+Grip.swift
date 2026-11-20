import Foundation

extension CoachingAnalysis {
    // Each corner's grip use on both laps (#558), against `options.gripEnvelope` or, without one,
    // the envelope the two laps themselves reached.
    // swiftlint:disable:next function_parameter_count
    static func readGrip(
        _ comparisons: inout [CornerComparison], lap: LapProfile, corners: [Corner], reference: LapProfile,
        referenceCorners: [Corner], options: CoachingOptions
    ) {
        guard
            let envelope = options.gripEnvelope
                ?? GripEnvelope.measure(points(of: lap) + points(of: reference), minimumPerSector: 4),
            let lapUse = GripUse.measure(lap, corners: corners, envelope: envelope, options: options.grip)
        else { return }
        let referenceUse = GripUse.measure(
            reference, corners: referenceCorners, envelope: envelope, options: options.grip)
        for index in comparisons.indices {
            let corner = comparisons[index].index
            comparisons[index].lapGrip = lapUse.corners.first { $0.index == corner }
            comparisons[index].referenceGrip = referenceUse?.corners.first { $0.index == corner }
        }
    }

    static func points(of profile: LapProfile) -> [(lateral: Double, longitudinal: Double)] {
        guard let lateral = profile.channels[.lateralG], let longitudinal = profile.channels[.longitudinalG] else {
            return []
        }
        return zip(lateral, longitudinal).map { ($0, $1) }
    }
}

extension CoachingNotes {
    /// Where braking stopped before turning, and grip left unused (#558), when the lap did worse
    /// than the reference at it.
    static func gripEvidence(_ context: Context) -> [String] {
        let format = context.format
        var lines: [String] = []
        if let gap = stoppedBeforeTurning(context) {
            let theirs = context.comparison.referenceGrip?.gap
            let kept = theirs.map { " (\(context.referencePhrase) kept \(format.g($0.lowestG)))" } ?? ""
            lines.append("Braking stopped before turning: combined G fell to \(format.g(gap.lowestG))\(kept)")
        }
        if let own = context.comparison.lapGrip?.meanUsed, let theirs = context.comparison.referenceGrip?.meanUsed,
            theirs - own > 0.1
        {
            lines.append(
                "Used \(Int((own * 100).rounded()))% of the grip through it against \(Int((theirs * 100).rounded()))%")
        }
        return lines
    }

    /// The lap's gap between braking and turning, when it fell below `gapBelow` of the limit and the
    /// reference kept clearly more grip there (or had no gap at all).
    static func stoppedBeforeTurning(_ context: Context) -> GripUse.Gap? {
        guard let gap = context.comparison.lapGrip?.gap, gap.lowestUsed < context.options.grip.gapBelow else {
            return nil
        }
        let theirs = context.comparison.referenceGrip?.gap
        return theirs.map({ $0.lowestUsed > gap.lowestUsed + 0.15 }) ?? true ? gap : nil
    }

    /// The braking-to-turning gap is the thing to try, for the kinds of loss it causes.
    static func gripSuggestion(_ context: Context) -> String? {
        guard stoppedBeforeTurning(context) != nil else { return nil }
        switch context.kind {
        case .coasting, .overSlowed, .brakedEarly, .brakedSofter:
            return "Keep a little brake on as you turn in, so the braking runs into the cornering rather than "
                + "stopping before it."
        default: return nil
        }
    }
}
