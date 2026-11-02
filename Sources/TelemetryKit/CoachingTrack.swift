import Foundation

/// Every complete lap of a session read against one reference, so the video can say, at any
/// moment, which corner is coming and what the coaching note for it is (#323).
///
/// Built once per compile: the reference's corners and the session's consistency are read once and
/// shared by every lap, which keeps a session of thirty laps to thirty profiles rather than nine
/// hundred.
public struct CoachingTrack: Sendable {
    public let referencePhrase: String
    public let reference: LapProfile
    /// By lap number.
    public let analyses: [Int: CoachingAnalysis]
    /// The laps analysed, in order.
    public let laps: [Lap]

    /// The corner in play at a moment: coming up, being driven, or just finished.
    public struct Moment: Sendable {
        public let lap: Lap
        public let analysis: CoachingAnalysis
        public let comparison: CornerComparison
        /// The phase the car is in; `nil` before the brake point and after the corner.
        public let phase: CornerPhase?
        /// Seconds until the brake point (positive on the approach, negative after it).
        public let secondsToBrakePoint: Double
        /// The corner is over and the card is being held for a moment.
        public let isHeld: Bool
    }

    /// `session`'s laps against `reference`. `nil` when the reference cannot be resolved or no lap
    /// can be read.
    public static func make(
        session: TelemetrySession, reference: CoachingReference, units: CoachingUnits = .metric,
        options: CoachingOptions = CoachingOptions()
    ) -> CoachingTrack? {
        guard let profile = reference.resolve(in: session, stepMeters: options.stepMeters) else { return nil }
        return make(
            session: session, reference: profile, referencePhrase: reference.phrase, sameSession: true, units: units,
            options: options)
    }

    /// `session`'s laps against a reference profile from this session or another.
    public static func make(
        session: TelemetrySession, reference: LapProfile, referencePhrase: String, sameSession: Bool,
        units: CoachingUnits = .metric, options: CoachingOptions = CoachingOptions()
    ) -> CoachingTrack? {
        let laps = LapDeltas.demotingShortLaps(session.laps, distance: session[.distance])
            .filter { $0.isComplete && $0.end != nil }
        guard !laps.isEmpty else { return nil }
        let reading = CoachingAnalysis.ReferenceReading(
            profile: reference, phrase: referencePhrase, sameSession: sameSession, session: session, options: options)
        var analyses: [Int: CoachingAnalysis] = [:]
        for lap in laps {
            guard let profile = LapProfile(lap: lap, in: session, stepMeters: options.stepMeters),
                let analysis = CoachingAnalysis.analyse(
                    lap: profile, in: session, against: reading, units: units, options: options)
            else { continue }
            analyses[lap.number] = analysis
        }
        guard !analyses.isEmpty else { return nil }
        return CoachingTrack(
            referencePhrase: referencePhrase, reference: reference, analyses: analyses,
            laps: laps.filter { analyses[$0.number] != nil })
    }

    /// The lap being driven at `inputTime` and its reading; `nil` between laps.
    public func analysis(atInputTime time: Double) -> (lap: Lap, analysis: CoachingAnalysis)? {
        guard let lap = laps.first(where: { $0.contains(time) }), let analysis = analyses[lap.number] else {
            return nil
        }
        return (lap, analysis)
    }

    /// The corner in play at `inputTime`: the one being driven; else the next one, from
    /// `leadSeconds` before its brake point; else the last one, for `holdSeconds` after its end.
    public func moment(atInputTime time: Double, leadSeconds: Double, holdSeconds: Double) -> Moment? {
        guard let (lap, analysis) = analysis(atInputTime: time) else { return nil }
        let profile = analysis.lap
        let elapsed = time - lap.start
        let distance = profile.distance(atElapsed: elapsed)
        var upcoming: (CornerComparison, Double)?
        var held: (CornerComparison, Double)?
        for comparison in analysis.corners {
            let metrics = comparison.lap
            let brakeAt = profile.elapsed(atDistance: metrics.phaseStart)
            let endAt = profile.elapsed(atDistance: metrics.corner.endDistance)
            if distance >= metrics.phaseStart, distance <= metrics.corner.endDistance {
                let phase = CornerPhase.allCases.first { phase in
                    metrics.phases[phase].map { $0.contains(distance) } ?? false
                }
                return Moment(
                    lap: lap, analysis: analysis, comparison: comparison, phase: phase ?? .exit,
                    secondsToBrakePoint: brakeAt - elapsed, isHeld: false)
            }
            if elapsed >= brakeAt - leadSeconds, elapsed < brakeAt {
                if upcoming == nil || brakeAt < upcoming?.1 ?? .infinity { upcoming = (comparison, brakeAt) }
            } else if elapsed > endAt, elapsed <= endAt + holdSeconds {
                if held == nil || endAt > held?.1 ?? -.infinity { held = (comparison, endAt) }
            }
        }
        if let (comparison, brakeAt) = upcoming {
            return Moment(
                lap: lap, analysis: analysis, comparison: comparison, phase: nil,
                secondsToBrakePoint: brakeAt - elapsed, isHeld: false)
        }
        if let (comparison, _) = held {
            let brakeAt = profile.elapsed(atDistance: comparison.lap.phaseStart)
            return Moment(
                lap: lap, analysis: analysis, comparison: comparison, phase: nil,
                secondsToBrakePoint: brakeAt - elapsed, isHeld: true)
        }
        return nil
    }
}
