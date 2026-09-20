import Foundation

/// Works out which way a channel means the car is turning, so a steering wheel or a g-force plot
/// can orient itself without being told.
///
/// Loggers disagree on the sign. RaceRender calls a right turn positive; ISO 8855 vehicle axes,
/// which RaceChrono follows, put +y to the left, so its `steering_angle` and `lateral_acc` are both
/// positive for a *left* turn. Rather than special-casing formats, measure it: the GPS heading says
/// which way the car actually went.
public enum TurnDirection {
    /// How a channel relates to a measured right turn.
    public struct Reading: Sendable, Equatable {
        /// Pearson correlation with a right-positive turn reference, −1…1. Negative means the
        /// channel is positive for a left turn and wants inverting.
        public let correlation: Double
        /// What the reference was derived from, for the status line.
        public let reference: Reference
        /// Samples that went into it.
        public let samples: Int

        public var invert: Bool { correlation < 0 }

        public init(correlation: Double, reference: Reference, samples: Int) {
            self.correlation = correlation
            self.reference = reference
            self.samples = samples
        }
    }

    public enum Reference: String, Sendable {
        /// Yaw rate from the GPS heading: ground truth, independent of any logger's convention.
        case gpsHeading
        /// Lateral acceleration, trusting `ChannelRole.lateralG`'s documented positive-is-right.
        case lateralG
    }

    /// Below this the reading is noise rather than a signal and is not worth acting on. The
    /// reference session correlates at 0.98; a car that barely turns correlates near zero.
    public static let minimumCorrelation = 0.5
    /// Fewer than this and the session is too short or too sparse to say anything.
    public static let minimumSamples = 60

    static let rate = 10.0
    /// Differentiating raw GPS bearing is hopeless — on the reference session it correlates −0.29
    /// with steering, against −0.98 once smoothed over about a second.
    static let smoothingSeconds = 1.0

    /// Yaw rate in degrees per second, positive clockwise (a right turn), from the heading channel.
    /// Returns `nil` when there is no usable heading.
    public static func yawRate(of session: TelemetrySession) -> Channel? {
        guard let heading = session[.heading], heading.count > 4 else { return nil }
        let smoothed = Resampler.smoothHeading(heading, windowSeconds: smoothingSeconds)
        var times: [Double] = []
        var values: [Double] = []
        times.reserveCapacity(smoothed.count)
        values.reserveCapacity(smoothed.count)
        for index in 1..<smoothed.count {
            let dt = smoothed.times[index] - smoothed.times[index - 1]
            guard dt > 0, dt < 2 else { continue }
            // Shortest way round the circle: a 359° → 1° step is +2°, not −358°.
            let delta =
                (smoothed.values[index] - smoothed.values[index - 1] + 540)
                .truncatingRemainder(dividingBy: 360) - 180
            times.append(smoothed.times[index])
            values.append(delta / dt)
        }
        guard times.count > 4 else { return nil }
        return Channel(role: .aux("yawRate"), name: "yaw rate", unit: .custom("deg/s"), times: times, values: values)
    }

    /// The reference a turn direction is measured against: GPS yaw where it exists, else lateral
    /// acceleration on the documented convention. `nil` when the session carries neither.
    public static func reference(in session: TelemetrySession) -> (channel: Channel, kind: Reference)? {
        if let yaw = yawRate(of: session) { return (yaw, .gpsHeading) }
        if let lateral = session[.lateralG], lateral.count > 4 { return (lateral, .lateralG) }
        return nil
    }

    /// How `channel` relates to a right turn in this session, or `nil` when the session cannot say
    /// — no reference, too few samples, or a car that barely turned.
    public static func reading(for channel: Channel, in session: TelemetrySession) -> Reading? {
        guard let (referenceChannel, kind) = reference(in: session), channel.count > 4 else { return nil }
        let a = SignalCorrelation.resample(times: channel.times, values: channel.values, rate: rate)
        let b = SignalCorrelation.resample(
            times: referenceChannel.times, values: referenceChannel.values, rate: rate)
        guard !a.values.isEmpty, !b.values.isEmpty else { return nil }

        // Line the two up on a shared clock before comparing: they are sampled from the same
        // session but need not start at the same instant.
        let start = max(a.start, b.start)
        let aOffset = Int(((start - a.start) * rate).rounded())
        let bOffset = Int(((start - b.start) * rate).rounded())
        let count = min(a.values.count - aOffset, b.values.count - bOffset)
        guard count >= minimumSamples else { return nil }
        let left = Array(a.values[aOffset..<(aOffset + count)])
        let right = Array(b.values[bOffset..<(bOffset + count)])

        guard let score = pearson(left, right) else { return nil }
        guard abs(score) >= minimumCorrelation else { return nil }
        return Reading(correlation: score, reference: kind, samples: count)
    }

    /// Pearson correlation, or `nil` when either series is flat (a parked car, a dead channel).
    static func pearson(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count == b.count, a.count > 1 else { return nil }
        let meanA = a.reduce(0, +) / Double(a.count)
        let meanB = b.reduce(0, +) / Double(b.count)
        var covariance = 0.0
        var varianceA = 0.0
        var varianceB = 0.0
        for (x, y) in zip(a, b) {
            let dx = x - meanA
            let dy = y - meanB
            covariance += dx * dy
            varianceA += dx * dx
            varianceB += dy * dy
        }
        guard varianceA > 0, varianceB > 0 else { return nil }
        let score = covariance / (varianceA * varianceB).squareRoot()
        return score.isFinite ? score : nil
    }
}
