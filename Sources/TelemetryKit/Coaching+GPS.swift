import Foundation

extension CoachingOptions {
    /// These options with distances said to the precision `session`'s positions allow (#555); as
    /// they are for a project saved before, which said them to the metre.
    func withGPSPrecision(of session: TelemetrySession) -> CoachingOptions {
        guard !session.legacyExactDistances, let gps = session.gpsQuality else { return self }
        var options = self
        options.distanceStepMeters = gps.distanceStep()
        return options
    }

    /// No difference finer than the GPS can place is judged (#555).
    var brakeTolerance: Double { max(brakePointToleranceMeters, distanceStepMeters) }
    var lateTolerance: Double { max(minimumSpeedLateMeters, distanceStepMeters) }
    var throttleTolerance: Double { max(throttleToleranceMeters, distanceStepMeters) }
}

extension CoachingAnalysis {
    /// Marks each corner where no position arrived somewhere between its braking and its exit, on
    /// the lap or on a reference from the same session (#555): where it braked is a guess there.
    static func markGPSGaps(
        _ comparisons: inout [CornerComparison], lap: LapProfile, reference: LapProfile?, delta: LapDeltaTrace,
        in session: TelemetrySession
    ) {
        guard !session.legacyExactDistances, let gps = session.gpsQuality, !gps.dropouts.isEmpty else { return }
        for index in comparisons.indices {
            let comparison = comparisons[index]
            let range =
                comparison.range ?? comparison.reference
                .phaseStart...max(comparison.reference.phaseStart, comparison.reference.phaseEnd)
            let onLap = gps.hasDropout(
                between: lap.sessionTime(atDistance: delta.lapDistance(atReferenceDistance: range.lowerBound)),
                and: lap.sessionTime(atDistance: delta.lapDistance(atReferenceDistance: range.upperBound)))
            let onReference = reference.map { reference in
                gps.hasDropout(
                    between: reference.sessionTime(atDistance: range.lowerBound),
                    and: reference.sessionTime(atDistance: range.upperBound))
            }
            comparisons[index].gpsGap = onLap || onReference == true
        }
    }
}
