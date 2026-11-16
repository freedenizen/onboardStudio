import Foundation

/// How much of the car's grip a lap used (#558), read against a `GripEnvelope`: on average and at
/// its peak through each corner, how much of the lap was near the limit, whether braking ran into
/// turning or stopped short of it, how long the car coasted, and how smoothly the G changed.
public struct GripUse: Hashable, Codable, Sendable {
    /// The thresholds, every one a parameter.
    public struct Options: Hashable, Codable, Sendable {
        /// The share of the limit that counts as at it.
        public var nearLimit: Double = 0.8
        /// Below this share of the limit between braking and turning is a gap.
        public var gapBelow: Double = 0.5
        /// Braking harder than this (g) is braking; turning harder than this is turning.
        public var braking: Double = 0.3
        public var turning: Double = 0.3
        /// Neither more than this much G, nor a pedal: coasting.
        public var coastingG: Double = 0.12

        public init() {}
    }

    /// Between peak braking and peak cornering, where the combined G fell.
    public struct Gap: Hashable, Codable, Sendable {
        /// The least of the limit used between the two, 0–1.
        public var lowestUsed: Double
        /// The combined G there, in g.
        public var lowestG: Double
        /// Seconds spent under `Options.gapBelow` of the limit between the two.
        public var seconds: Double
        /// Metres into the lap where the combined G was lowest.
        public var at: Double
    }

    public struct Corner: Hashable, Codable, Sendable {
        public var index: Int
        /// The corner's name or number, as Coaching says it after "Turn".
        public var label: String
        public var meanUsed: Double
        public var peakUsed: Double
        /// The share of the corner's time at or above `Options.nearLimit`.
        public var nearLimit: Double
        /// `nil` when the corner was not braked for, or not turned in, hard enough to have one.
        public var gap: Gap?
    }

    /// The lap's average use of the limit while braking or turning.
    public var meanUsed: Double
    /// The share of the lap's time at or above `Options.nearLimit`.
    public var nearLimit: Double
    /// Seconds with neither G nor a pedal.
    public var coastingSeconds: Double
    /// How fast the combined G changed, root mean square, in g a second: lower is smoother.
    public var roughness: Double
    public var corners: [Corner]
}

/// A lap's G, kept small enough to keep (#558): every few metres, the seconds, the lateral and
/// longitudinal G and the pedals, and where its corners were. A logbook session keeps its best
/// lap's, so its grip can be read again against a limit learned later.
public struct GripTrace: Hashable, Codable, Sendable {
    public struct CornerSpan: Hashable, Codable, Sendable {
        public var label: String
        public var start: Double
        public var apex: Double
        public var end: Double

        public init(label: String, start: Double, apex: Double, end: Double) {
            self.label = label
            self.start = start
            self.apex = apex
            self.end = end
        }
    }

    public var stepMeters: Double
    public var elapsed: [Double]
    public var lateral: [Double]
    public var longitudinal: [Double]
    /// 0–100, when the logger recorded them.
    public var throttle: [Double]?
    public var brake: [Double]?
    public var corners: [CornerSpan]

    public var count: Int { elapsed.count }

    public init(
        stepMeters: Double, elapsed: [Double], lateral: [Double], longitudinal: [Double], throttle: [Double]?,
        brake: [Double]?, corners: [CornerSpan]
    ) {
        self.stepMeters = stepMeters
        self.elapsed = elapsed
        self.lateral = lateral
        self.longitudinal = longitudinal
        self.throttle = throttle
        self.brake = brake
        self.corners = corners
    }

    /// `profile` every `stepMeters`, with `corners` named by `labels`; `nil` without G.
    public init?(_ profile: LapProfile, corners: [Corner], labels: [String] = [], stepMeters: Double = 5) {
        guard let lateral = profile.channels[.lateralG], let longitudinal = profile.channels[.longitudinalG],
            let length = profile.distances.last, length > stepMeters * 4
        else { return nil }
        let every = max(1, Int((stepMeters / profile.stepMeters).rounded()))
        let picks = Array(stride(from: 0, to: profile.count, by: every))
        self.stepMeters = profile.stepMeters * Double(every)
        elapsed = picks.map { profile.elapsed[$0] }
        self.lateral = picks.map { lateral[$0] }
        self.longitudinal = picks.map { longitudinal[$0] }
        throttle = profile.channels[.throttle].map { values in picks.map { values[$0] } }
        brake = profile.channels[.brake].map { values in picks.map { values[$0] } }
        self.corners = corners.enumerated().map { index, corner in
            CornerSpan(
                label: index < labels.count ? labels[index] : String(index + 1), start: corner.startDistance,
                apex: corner.apexDistance, end: corner.endDistance)
        }
    }
}

extension GripUse {
    /// `profile`'s use of `envelope`, through `corners` (distances into the profile).
    public static func measure(
        _ profile: LapProfile, corners: [TelemetryKit.Corner], envelope: GripEnvelope, options: Options = Options()
    ) -> GripUse? {
        GripTrace(profile, corners: corners, stepMeters: profile.stepMeters).flatMap {
            measure($0, envelope: envelope, options: options)
        }
    }

    /// `trace`'s use of `envelope`.
    public static func measure(_ trace: GripTrace, envelope: GripEnvelope, options: Options = Options()) -> GripUse? {
        let count = trace.count
        guard count >= 4 else { return nil }
        let lateral = trace.lateral
        let longitudinal = trace.longitudinal
        let used = (0..<count).map { envelope.used(lateral: lateral[$0], longitudinal: longitudinal[$0]) }
        let combined = (0..<count).map { hypot(lateral[$0], longitudinal[$0]) }
        // Seconds each point stands for.
        let dt = (0..<count).map { index in
            index + 1 < count ? max(0, trace.elapsed[index + 1] - trace.elapsed[index]) : 0
        }
        let total = dt.reduce(0, +)
        guard total > 0 else { return nil }

        var working = 0.0
        var workingTime = 0.0
        var near = 0.0
        var coasting = 0.0
        var jerk = 0.0
        for index in 0..<count {
            let busy = -longitudinal[index] >= options.braking || abs(lateral[index]) >= options.turning
            if busy {
                working += used[index] * dt[index]
                workingTime += dt[index]
            }
            if used[index] >= options.nearLimit { near += dt[index] }
            let pedal = (trace.throttle?[index] ?? 0) > 5 || (trace.brake?[index] ?? 0) > 5
            if combined[index] < options.coastingG, !pedal { coasting += dt[index] }
            if index > 0, dt[index - 1] > 0 {
                let rate = (combined[index] - combined[index - 1]) / dt[index - 1]
                jerk += rate * rate * dt[index - 1]
            }
        }
        let series = Series(used: used, combined: combined, dt: dt, lateral: lateral, longitudinal: longitudinal)
        let readings = trace.corners.enumerated().map { index, corner in
            measure(corner, index: index, step: trace.stepMeters, series: series, options: options)
        }
        return GripUse(
            meanUsed: workingTime > 0 ? working / workingTime : 0, nearLimit: near / total, coastingSeconds: coasting,
            roughness: (jerk / total).squareRoot(), corners: readings)
    }

    /// A trace's values at each point, as the corner readings need them.
    private struct Series {
        let used: [Double]
        let combined: [Double]
        let dt: [Double]
        let lateral: [Double]
        let longitudinal: [Double]
    }

    private static func measure(
        _ corner: GripTrace.CornerSpan, index: Int, step: Double, series: Series, options: Options
    ) -> Corner {
        let count = series.used.count
        // From the braking into it: up to 200 m before it begins.
        let first = max(0, Int(((corner.start - 200) / step).rounded(.down)))
        let last = min(count - 1, Int((corner.end / step).rounded(.up)))
        guard first < last else {
            return Corner(index: index, label: corner.label, meanUsed: 0, peakUsed: 0, nearLimit: 0, gap: nil)
        }
        let inCorner = min(last, max(first, Int((corner.start / step).rounded(.down))))...last
        var sum = 0.0
        var time = 0.0
        var near = 0.0
        for point in inCorner {
            sum += series.used[point] * series.dt[point]
            time += series.dt[point]
            if series.used[point] >= options.nearLimit { near += series.dt[point] }
        }
        let peak = inCorner.map { series.used[$0] }.max() ?? 0

        // Peak braking before the apex, then peak cornering after it.
        let apex = min(last, max(first, Int((corner.apex / step).rounded())))
        var gap: Gap?
        if let braked = (first...apex).min(by: { series.longitudinal[$0] < series.longitudinal[$1] }),
            -series.longitudinal[braked] >= options.braking,
            let turned = (braked...last).max(by: { abs(series.lateral[$0]) < abs(series.lateral[$1]) }),
            abs(series.lateral[turned]) >= options.turning, turned > braked,
            let lowest = (braked...turned).min(by: { series.used[$0] < series.used[$1] })
        {
            let seconds = (braked...turned).filter { series.used[$0] < options.gapBelow }.reduce(0) {
                $0 + series.dt[$1]
            }
            gap = Gap(
                lowestUsed: series.used[lowest], lowestG: series.combined[lowest], seconds: seconds,
                at: Double(lowest) * step)
        }
        return Corner(
            index: index, label: corner.label, meanUsed: time > 0 ? sum / time : 0, peakUsed: peak,
            nearLimit: time > 0 ? near / time : 0, gap: gap)
    }
}
