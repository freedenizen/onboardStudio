import Foundation

/// The four parts of a corner a coach talks about, in the order they are driven.
///
/// They tile a window around the corner, so the time lost in the phases adds up to the time
/// lost in the corner: braking runs from the brake point to turn-in, entry from turn-in to the
/// minimum-speed point, apex from there to throttle pick-up, exit from pick-up to the corner's
/// end or full throttle.
public enum CornerPhase: String, CaseIterable, Sendable, Codable {
    case braking
    case entry
    case apex
    case exit

    public var displayName: String {
        switch self {
        case .braking: "Braking"
        case .entry: "Entry"
        case .apex: "Apex"
        case .exit: "Exit"
        }
    }
}

/// How one corner was driven on one lap: where the brakes went on and came off, how slow the car
/// got and where, when the throttle came back, and the phases that follow from those.
///
/// Distances are metres into the lap unless the name says otherwise; the `…Meters` values that
/// are relative to the apex are negative before it and positive after. Every pedal measurement
/// says where it came from, because a GoPro or a phone records no pedals and the brake point then
/// comes from the speed trace, which is a different kind of number and should be shown as one.
public struct CornerMetrics: Sendable, Equatable, Codable {
    /// What a pedal measurement was read from.
    public enum Source: String, Sendable, Codable {
        /// The brake channel: a switch or a position.
        case brakeChannel
        /// A brake pressure channel.
        case brakePressure
        /// The throttle channel.
        case throttleChannel
        /// A recorded accelerometer.
        case accelerometer
        /// Deceleration worked out from the speed trace.
        case speedTrace

        public var displayName: String {
            switch self {
            case .brakeChannel: "the brake channel"
            case .brakePressure: "brake pressure"
            case .throttleChannel: "the throttle channel"
            case .accelerometer: "the accelerometer"
            case .speedTrace: "the speed trace"
            }
        }
    }

    /// Thresholds for reading a corner. Pedal thresholds are fractions of the channel's own range
    /// over the lap, so a 0–1 switch, a 0–100 % position and a bar of pressure all work; the
    /// accelerations are in g. None is tied to a logger.
    public struct Options: Sendable, Hashable {
        /// A brake channel above this fraction of its range is "on".
        public var brakeOnFraction: Double
        /// A throttle channel above this fraction of its range is "on".
        public var throttleOnFraction: Double
        /// A throttle channel above this fraction of its range is "full".
        public var fullThrottleFraction: Double
        /// Without a brake channel, deceleration at or beyond this is braking.
        public var brakingDecelerationG: Double
        /// Without a throttle channel, acceleration at or beyond this is the throttle coming back.
        public var acceleratingG: Double
        /// How far before a corner's turn-in to look for its brake point.
        public var approachMeters: Double
        /// A pedal gap shorter than this does not end its application (a brake re-applied while
        /// trail braking is one braking, not two).
        public var pedalGapMeters: Double
        /// Lateral G above this fraction of the corner's peak counts as cornering, for trail braking.
        public var corneringLateralFraction: Double

        public init(
            brakeOnFraction: Double = 0.05, throttleOnFraction: Double = 0.05, fullThrottleFraction: Double = 0.9,
            brakingDecelerationG: Double = 0.25, acceleratingG: Double = 0.05, approachMeters: Double = 300,
            pedalGapMeters: Double = 10, corneringLateralFraction: Double = 0.3
        ) {
            self.brakeOnFraction = min(max(brakeOnFraction, 0), 1)
            self.throttleOnFraction = min(max(throttleOnFraction, 0), 1)
            self.fullThrottleFraction = min(max(fullThrottleFraction, 0), 1)
            self.brakingDecelerationG = max(0.01, brakingDecelerationG)
            self.acceleratingG = max(0, acceleratingG)
            self.approachMeters = max(0, approachMeters)
            self.pedalGapMeters = max(0, pedalGapMeters)
            self.corneringLateralFraction = min(max(corneringLateralFraction, 0), 1)
        }
    }

    public let corner: Corner
    /// Which corner it is in the reference's list, so the same corner on two laps can be paired.
    public let index: Int
    /// Metres into the lap of the stretch searched: back to the previous corner's end (or the
    /// approach distance), forward to the next corner's start.
    public let searchRange: ClosedRange<Double>

    /// Metres before the apex at which braking began; `nil` when the car never braked for it.
    public var brakePointMeters: Double?
    public var brakeSource: Source?
    /// The hardest deceleration while braking, in g (positive).
    public var peakBrakingG: Double?
    /// Where the brakes came off, relative to the apex.
    public var brakeReleaseMeters: Double?
    /// Metres over which the brakes were still on while the car was already cornering.
    public var trailBrakingMeters: Double?
    /// Speed at turn-in, m/s.
    public var entrySpeed: Double
    /// The slowest the car got, m/s, and where relative to the apex.
    public var minimumSpeed: Double
    public var minimumSpeedMeters: Double
    /// Speed at the corner's end, m/s.
    public var exitSpeed: Double
    /// Where the throttle came back, relative to the apex.
    public var throttlePickupMeters: Double?
    public var throttleSource: Source?
    /// Where the throttle reached full, relative to the apex; only a throttle channel can say.
    public var fullThrottleMeters: Double?
    /// Seconds with neither pedal applied between the brake point and the corner's end; only
    /// recorded pedals can say.
    public var coastingSeconds: Double?
    /// The most lateral G in the corner (unsigned).
    public var peakLateralG: Double?
    /// Seconds from turn-in to the corner's end.
    public var timeInCorner: Double
    /// Root-mean-square steering change per metre through the corner, in the steering channel's
    /// own unit; comparable between laps of one logger, not between loggers.
    public var steeringSmoothness: Double?
    /// The stretch of lap each phase covers, metres into the lap; phases tile from the brake
    /// point (or turn-in) to the corner's end or full throttle.
    public var phases: [CornerPhase: ClosedRange<Double>]

    /// Metres into the lap where the phases begin and end.
    public var phaseStart: Double { phases[.braking]?.lowerBound ?? corner.startDistance }
    public var phaseEnd: Double { phases[.exit]?.upperBound ?? corner.endDistance }
}
