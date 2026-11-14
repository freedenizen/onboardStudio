import Foundation

/// What a lap is measured against.
public enum CoachingReference: Sendable, Hashable, Codable {
    /// The session's quickest complete lap.
    case sessionBest
    /// A particular lap of the same session.
    case lap(Int)
    /// The quickest lap-length stretch of the session, starting anywhere: what MoTeC calls the
    /// fastest rolling lap. The timing line often cuts a driver's best run of corners in two.
    case fastestRolling
    /// The best sector of each lap joined into one: the lap the driver has already shown they
    /// can do. MoTeC's eclectic lap, Garmin's True Optimal Lap.
    case compositeOptimal

    public var displayName: String {
        switch self {
        case .sessionBest: "Best lap"
        case .lap(let number): "Lap \(number)"
        case .fastestRolling: "Fastest rolling lap"
        case .compositeOptimal: "Optimal lap (spliced)"
        }
    }

    /// How a note names it: "… than your best lap".
    public var phrase: String {
        switch self {
        case .sessionBest: "your best lap"
        case .lap(let number): "lap \(number)"
        case .fastestRolling: "the rolling lap"
        case .compositeOptimal: "the optimal lap"
        }
    }
}

/// The quickest window of one lap's length anywhere in a session.
public enum RollingLap {
    /// Where the fastest rolling lap of `lengthMeters` (by default the median complete lap's
    /// length) begins and ends. Looked for within the complete laps only, so an out lap or the
    /// pit lane can never be part of it. `nil` without laps or a distance channel.
    public static func fastestWindow(in session: TelemetrySession, lengthMeters: Double? = nil) -> LapProfile.Window? {
        // A rolling lap runs on past the line into the next lap; a run's course ends at the finish
        // and the next run starts somewhere else, so there is nothing to roll into (#552).
        guard let distance = session[.distance], !session.laps.areRuns else { return nil }
        let laps = LapDeltas.demotingShortLaps(session.laps, distance: distance)
            .filter { $0.isComplete && $0.end != nil }
        guard let first = laps.first, let last = laps.last, let lastEnd = last.end else { return nil }
        let lengths = laps.compactMap { LapComparison.length(of: $0, distance: distance) }.sorted()
        guard !lengths.isEmpty else { return nil }
        let length = lengthMeters ?? lengths[lengths.count / 2]
        guard length > 0 else { return nil }

        let times = distance.times
        let values = distance.values
        var start = times.firstIndex(atOrAfter: first.start)
        let stop = min(times.firstIndex(atOrAfter: lastEnd), times.count - 1)
        var end = start
        var best: LapProfile.Window?
        while start < stop {
            let target = values[start] + length
            while end < stop, values[end] < target { end += 1 }
            guard values[end] >= target else { break }
            // The moment the window's length was reached, between the two samples around it.
            let previous = max(start, end - 1)
            let span = values[end] - values[previous]
            let fraction = span > 0 ? (target - values[previous]) / span : 1
            let endTime = times[previous] + (times[end] - times[previous]) * fraction
            let duration = endTime - times[start]
            // A later window must be quicker by more than rounding to take over, so steady laps
            // give the first lap rather than wherever floating point happened to dip.
            if best == nil || duration < (best?.duration ?? .infinity) - 1e-3 {
                best = LapProfile.Window(start: times[start], end: endTime)
            }
            start += 1
        }
        return best
    }

    /// The fastest rolling lap as a profile re-based to the start/finish line, so its distances
    /// are distances into a lap and its corners line up with every other lap's. Two pieces when
    /// the window straddles the line; one, identical to that lap's profile, when it does not.
    public static func profile(in session: TelemetrySession, stepMeters: Double = 2) -> LapProfile? {
        guard let window = fastestWindow(in: session), let distance = session[.distance],
            let startLap = session.laps.lap(containing: window.start), let startLapEnd = startLap.end,
            let into = LapComparison.distanceIntoLap(at: window.start, lap: startLap, distance: distance),
            let startLength = LapComparison.length(of: startLap, distance: distance)
        else { return nil }
        let label = CoachingReference.fastestRolling.displayName
        if into < 1, window.end <= startLapEnd + 1e-6 {
            return LapProfile.spliced(
                [.init(lap: startLap, from: 0, to: startLength)], in: session, label: label, stepMeters: stepMeters)
        }
        guard let endLap = session.laps.lap(containing: window.end - 1e-6) ?? session.laps.last,
            let intoEnd = LapComparison.distanceIntoLap(at: window.end, lap: endLap, distance: distance)
        else { return nil }
        guard endLap.number != startLap.number else {
            return LapProfile.spliced(
                [.init(lap: startLap, from: into, to: intoEnd)], in: session, label: label, stepMeters: stepMeters)
        }
        return LapProfile.spliced(
            [.init(lap: endLap, from: 0, to: intoEnd), .init(lap: startLap, from: into, to: startLength)], in: session,
            label: label, stepMeters: stepMeters)
    }
}

/// The best sector of each lap, joined into one lap.
public enum CompositeLap {
    /// The optimal lap as a profile: sector by sector, the lap that set the best time, cut over
    /// that sector's distances and joined to the next. Its duration is `analysis.theoreticalLapTime`.
    /// `nil` until every sector has been timed once.
    public static func optimal(
        in session: TelemetrySession, analysis: SectorAnalysis, stepMeters: Double = 2
    ) -> LapProfile? {
        let bests = analysis.best
        guard bests.allSatisfy({ $0 != nil }) else { return nil }
        let cuts: [LapProfile.Cut] = bests.enumerated().compactMap { index, best in
            guard let best, let lap = session.laps.first(where: { $0.number == best.lapNumber }) else { return nil }
            let range = analysis.layout.range(of: index)
            return LapProfile.Cut(lap: lap, from: range.lowerBound, to: range.upperBound)
        }
        guard cuts.count == bests.count else { return nil }
        return LapProfile.spliced(
            cuts, in: session, label: CoachingReference.compositeOptimal.displayName, stepMeters: stepMeters)
    }
}

extension CoachingReference {
    /// The profile this reference names in `session`, or `nil` when the session cannot supply it
    /// (no such lap, no complete laps, sectors not all timed). The optimal lap uses the session's
    /// own sectors when it has them, so it agrees with the Sector Times panel, and corner-aware
    /// sectors otherwise, which keep the joins off the corners.
    public func resolve(in session: TelemetrySession, stepMeters: Double = 2) -> LapProfile? {
        switch self {
        case .sessionBest:
            return LapDeltas.sessionBest(in: session)
                .flatMap { LapProfile(lap: $0, in: session, stepMeters: stepMeters) }
        case .lap(let number):
            return session.laps.first { $0.number == number && $0.isComplete }
                .flatMap { LapProfile(lap: $0, in: session, stepMeters: stepMeters) }
        case .fastestRolling:
            return RollingLap.profile(in: session, stepMeters: stepMeters)
        case .compositeOptimal:
            let analysis =
                session.sectors ?? Sectors.analyse(mode: .cornerAware(count: SectorMode.defaultCount), session: session)
            return analysis.flatMap { CompositeLap.optimal(in: session, analysis: $0, stepMeters: stepMeters) }
        }
    }
}
