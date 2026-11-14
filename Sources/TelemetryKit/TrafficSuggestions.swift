import Foundation

/// A corner of one lap the telemetry says may have been traffic (#572): a place for the driver to
/// look, never a verdict. A lift where the other laps are flat out looks the same whether a car
/// was in the way or the driver made a mistake, so a suggestion changes nothing in the coaching
/// until the driver marks the corner; dismissing it is remembered.
public struct TrafficSuggestion: Sendable, Hashable, Codable, Identifiable {
    /// What the telemetry saw.
    public enum Evidence: Sendable, Hashable, Codable {
        /// The lap lifted for `meters` where most of the session's other laps were flat out; read
        /// from the throttle channel, or without one, the lap slowed where the others did not.
        case lift(meters: Double, fromThrottle: Bool)
        /// The corner, from its braking to the next corner's, took `seconds` longer than on a
        /// typical lap of the session, many times more than its laps usually differ by.
        case slow(seconds: Double)
    }

    public var id: String { "\(lapNumber).\(corner)" }
    public let lapNumber: Int
    /// The corner's index in the reference's list, as `CornerComparison.index`.
    public let corner: Int
    /// What the circuit calls it ("4", "3a"), else its number.
    public let label: String
    /// The corner's stretch on the lap, in session time: from its brake point to the next
    /// corner's, on the session's quickest lap.
    public let window: LapProfile.Window
    public let evidence: [Evidence]

    public init(lapNumber: Int, corner: Int, label: String, window: LapProfile.Window, evidence: [Evidence]) {
        self.lapNumber = lapNumber
        self.corner = corner
        self.label = label
        self.window = window
        self.evidence = evidence
    }

    /// "You lifted for 40 m where most of your other laps were flat out, and Turn 3 took 1.20 s
    /// longer than it usually does"
    public func sentence(units: CoachingUnits) -> String {
        let format = CoachingNotes.Formatter(units: units)
        let parts = evidence.map { evidence -> String in
            switch evidence {
            case .lift(let meters, true):
                "you lifted for \(format.metres(meters)) where most of your other laps were flat out"
            case .lift(let meters, false):
                "you slowed for \(format.metres(meters)) where most of your other laps did not"
            case .slow(let seconds):
                "Turn \(label) took \(format.seconds(seconds)) longer than it usually does"
            }
        }
        let joined = parts.formatted(.list(type: .and))
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }
}

/// Finds the corners of a session the telemetry says may have been traffic (#572), by comparing
/// each lap with the session's other laps at the same place. Nothing here is tied to a logger:
/// the throttle is read as a fraction of its own range, and without one the speed trace is used.
///
/// Each corner owns the lap from its brake point to the next corner's, as the corner table divides
/// it, so the slow run out of it and a lift on the straight after, which is how following a slower
/// car looks, count towards the corner whose time they cost.
public enum TrafficSuggestions {
    public struct Options: Sendable, Hashable {
        /// A lift shorter than this is a brake point a little early, not a car in the way.
        public var minimumLiftMeters: Double
        /// A throttle below this fraction of its range is lifted.
        public var liftFraction: Double
        /// A throttle at or above this fraction of its range is flat out.
        public var fullThrottleFraction: Double
        /// Without a throttle channel, slowing at least this hard (g) is a lift, and a lap slowing
        /// by less than half of it is not slowing.
        public var slowingG: Double
        /// A corner must take at least this much longer than usual to be suggested…
        public var minimumSlowSeconds: Double
        /// …and this many times more than the corner's laps usually differ by.
        public var spreadMultiple: Double
        /// Laps more than this fraction slower than the best (a cool-down lap, a lap under a full
        /// course caution) are neither read nor compared with.
        public var maximumLapTolerance: Double
        /// Fewer laps than this say nothing about what is usual.
        public var minimumLaps: Int

        public init(
            minimumLiftMeters: Double = 20, liftFraction: Double = 0.5, fullThrottleFraction: Double = 0.9,
            slowingG: Double = 0.1, minimumSlowSeconds: Double = 0.5, spreadMultiple: Double = 2,
            maximumLapTolerance: Double = 0.5, minimumLaps: Int = 3
        ) {
            self.minimumLiftMeters = max(0, minimumLiftMeters)
            self.liftFraction = min(max(liftFraction, 0), 1)
            self.fullThrottleFraction = min(max(fullThrottleFraction, 0), 1)
            self.slowingG = max(0.01, slowingG)
            self.minimumSlowSeconds = max(0, minimumSlowSeconds)
            self.spreadMultiple = max(0, spreadMultiple)
            self.maximumLapTolerance = max(0, maximumLapTolerance)
            self.minimumLaps = max(2, minimumLaps)
        }
    }

    /// Every suggestion in `session`, by lap and then corner, leaving out any corner a traffic mark
    /// already covers a quarter of (as a mark leaves a corner out) and any the driver dismissed.
    /// `corners` are the reference's, read on every lap at the same distance, as
    /// `ConsistencyStats` reads them.
    public static func find(
        in session: TelemetrySession, corners: [Corner], options: CoachingOptions = CoachingOptions()
    ) -> [TrafficSuggestion] {
        let settings = options.trafficSuggestions
        let complete = LapDeltas.demotingShortLaps(session.laps, distance: session[.distance])
            .filter { $0.isComplete && $0.duration != nil }
        guard let best = complete.compactMap(\.duration).min(), !corners.isEmpty else { return [] }
        let profiles = complete.filter { ($0.duration ?? .infinity) <= best * (1 + settings.maximumLapTolerance) }
            .compactMap { LapProfile(lap: $0, in: session, stepMeters: options.stepMeters) }
        guard profiles.count >= settings.minimumLaps else { return [] }
        let labels = session.cornerNames(for: corners).map(\.label)
        guard let quickest = profiles.min(by: { $0.duration < $1.duration }) else { return [] }
        let bounds = boundaries(of: corners, on: quickest, options: options)
        let lifts = lifts(in: profiles, options: settings, step: options.stepMeters)
        let slow = slowCorners(in: profiles, bounds: bounds, options: settings)
        var suggestions: [TrafficSuggestion] = []
        for (lap, profile) in profiles.enumerated() {
            guard let number = profile.pieces.first?.lapNumber else { continue }
            for corner in corners.indices {
                let from = bounds[corner] * profile.lengthMeters
                let to = bounds[corner + 1] * profile.lengthMeters
                var evidence: [TrafficSuggestion.Evidence] = []
                let inside = lifts[lap].filter { from <= $0.counted && $0.counted < to }
                if let fromThrottle = inside.first?.fromThrottle {
                    evidence.append(.lift(meters: inside.reduce(0) { $0 + $1.meters }, fromThrottle: fromThrottle))
                }
                if let seconds = slow[lap][corner] { evidence.append(.slow(seconds: seconds)) }
                guard !evidence.isEmpty else { continue }
                let window = LapProfile.Window(
                    start: profile.sessionTime(atDistance: from), end: profile.sessionTime(atDistance: to))
                guard !answered(window, in: session) else { continue }
                suggestions.append(
                    TrafficSuggestion(
                        lapNumber: number, corner: corner,
                        label: corner < labels.count ? labels[corner] : "\(corner + 1)", window: window,
                        evidence: evidence))
            }
        }
        return suggestions
    }

    /// Whether the driver has already said what `window` was: a mark covering a quarter of it, as
    /// a mark covering a quarter of a corner leaves the corner out, or a dismissal covering half.
    static func answered(_ window: LapProfile.Window, in session: TelemetrySession) -> Bool {
        session.traffic.contains { shared($0.start...$0.end, window) >= window.duration / 4 }
            || session.dismissedTraffic.contains { shared($0.start...$0.end, window) >= window.duration / 2 }
    }

    /// Seconds `range` and `window` have in common; more than zero only when they truly overlap.
    static func shared(_ range: ClosedRange<Double>, _ window: LapProfile.Window) -> Double {
        let common = min(range.upperBound, window.end) - max(range.lowerBound, window.start)
        return common > 1e-6 ? common : -1
    }

    /// Where each corner's stretch begins, as a fraction of the lap, and where the last ends: at
    /// `quickest`'s brake point for each corner after the first, as the corner table divides the
    /// lap (a corner's exit runs on to the next one's braking), from the lap's start to its end.
    static func boundaries(of corners: [Corner], on quickest: LapProfile, options: CoachingOptions) -> [Double] {
        let length = quickest.lengthMeters
        guard length > 0 else { return [0, 1] }
        let metrics = CornerMetrics.measure(corners: corners, of: quickest, options: options.metrics)
        var bounds = [0.0]
        for index in corners.indices.dropFirst() {
            let start = metrics.first { $0.index == index }?.phaseStart ?? corners[index].startDistance
            bounds.append(min(max(start / length, bounds[bounds.count - 1]), 1))
        }
        bounds.append(1)
        return bounds
    }

    // MARK: - Lifts

    /// A stretch one lap lifted through, metres into the lap.
    struct Lift {
        /// Where it is counted: 10 m past its end. A lift that runs up to a corner, as braking
        /// early behind a slower car does, counts towards that corner, as the corner table counts
        /// braking early; one that ends partway along a straight stays with the exit before it.
        let counted: Double
        let meters: Double
        let fromThrottle: Bool
    }

    /// How each lap is read for a lift: lifted, and "flat out" for the laps it is compared with.
    struct LiftReading {
        let role: ChannelRole
        let isLifted: (Double) -> Bool
        let isFlat: (Double) -> Bool
    }

    static func liftReading(of profiles: [LapProfile], options: Options) -> LiftReading? {
        if profiles.allSatisfy({ $0.source(of: .throttle) == .recorded }) {
            let values = profiles.compactMap { $0.channels[.throttle] }.joined()
            guard let low = values.min(), let high = values.max(), high > low else { return nil }
            let lift = low + (high - low) * options.liftFraction
            let full = low + (high - low) * options.fullThrottleFraction
            return LiftReading(role: .throttle, isLifted: { $0 < lift }, isFlat: { $0 >= full })
        }
        guard profiles.allSatisfy({ $0.has(.longitudinalG) }) else { return nil }
        let slowing = options.slowingG
        return LiftReading(
            role: .longitudinalG, isLifted: { $0 <= -slowing }, isFlat: { $0 > -slowing / 2 })
    }

    /// For each lap, the stretches where it lifted and most of the others were flat out, read at
    /// the same fraction of each lap so laps of slightly different lengths line up.
    static func lifts(in profiles: [LapProfile], options: Options, step: Double) -> [[Lift]] {
        guard let reading = liftReading(of: profiles, options: options),
            let longest = profiles.map(\.lengthMeters).max(), longest > 0
        else { return profiles.map { _ in [] } }
        let points = max(2, Int(longest / max(0.5, step)) + 1)
        let fractions = (0..<points).map { Double($0) / Double(points - 1) }
        let values: [[Double]] = profiles.map { profile in
            fractions.map { profile.value(of: reading.role, atDistance: $0 * profile.lengthMeters) ?? .nan }
        }
        let flat = values.map { $0.map(reading.isFlat) }
        let gapPoints = Int((10 / max(0.5, step)).rounded())
        return profiles.indices.map { lap in
            let others = profiles.count - 1
            let lifted = fractions.indices.map { point -> Bool in
                guard reading.isLifted(values[lap][point]) else { return false }
                let flatOthers = flat.indices.filter { $0 != lap && flat[$0][point] }.count
                return flatOthers * 2 > others
            }
            return runs(of: lifted, bridging: gapPoints).compactMap { run -> Lift? in
                let from = fractions[run.lowerBound] * profiles[lap].lengthMeters
                let to = fractions[run.upperBound] * profiles[lap].lengthMeters
                guard to - from >= options.minimumLiftMeters else { return nil }
                return Lift(counted: to + 10, meters: to - from, fromThrottle: reading.role == .throttle)
            }
        }
    }

    /// The runs of `true`, with gaps of up to `bridging` points joined.
    static func runs(of flags: [Bool], bridging: Int) -> [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        for index in flags.indices where flags[index] {
            if let last = runs.last, index - last.upperBound <= bridging + 1 {
                runs[runs.count - 1] = last.lowerBound...index
            } else {
                runs.append(index...index)
            }
        }
        return runs
    }

    // MARK: - Slow corners

    /// For each lap and corner, the seconds the corner's stretch took beyond its usual time, when
    /// that is more than the minimum and more than a multiple of how much the laps usually differ
    /// there; `nil` otherwise. Usual is read from the quicker half of the laps (their median, and
    /// their median absolute deviation for the spread): traffic only ever makes a corner slower,
    /// and where half the laps were held up, the median of them all is one of the held-up laps.
    static func slowCorners(in profiles: [LapProfile], bounds: [Double], options: Options) -> [[Double?]] {
        let times = profiles.map { profile in
            zip(bounds, bounds.dropFirst()).map { from, to in
                profile.elapsed(atDistance: to * profile.lengthMeters)
                    - profile.elapsed(atDistance: from * profile.lengthMeters)
            }
        }
        var slow = profiles.map { _ in [Double?](repeating: nil, count: bounds.count - 1) }
        for corner in 0..<(bounds.count - 1) {
            let readings = times.map { $0[corner] }
            let quicker = Array(readings.sorted().prefix((readings.count + 1) / 2))
            let usual = median(quicker)
            let spread = 1.4826 * median(quicker.map { abs($0 - usual) })
            let threshold = max(options.minimumSlowSeconds, options.spreadMultiple * spread)
            for lap in profiles.indices where readings[lap] - usual >= threshold {
                slow[lap][corner] = readings[lap] - usual
            }
        }
        return slow
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

extension CoachingAnalysis {
    /// Hangs each of the lap's suggestions on its corner; a corner already marked takes none.
    static func attach(_ suggestions: [TrafficSuggestion], to comparisons: inout [CornerComparison], lap: LapProfile) {
        guard !lap.isSpliced, let number = lap.pieces.first?.lapNumber else { return }
        for suggestion in suggestions where suggestion.lapNumber == number {
            guard let index = comparisons.firstIndex(where: { $0.index == suggestion.corner }),
                comparisons[index].traffic == nil
            else { continue }
            comparisons[index].suggestion = suggestion
        }
    }
}
