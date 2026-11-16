import Foundation

/// A second logger lined up with the first by what both recorded (#562): an ECU log with RPM and
/// pressures but no GPS, whose clock seldom agrees with the GPS logger's, slid along until a channel
/// they share — RPM above all — reads the same in both.
public enum DataAlignment {
    /// The channels tried, in order: the ones that change most and mean the same in any logger.
    public static let preferredRoles: [ChannelRole] = [
        .rpm, .speed, .throttle, .longitudinalG, .lateralG, .brake, .gear,
    ]

    public struct Result: Sendable, Equatable {
        /// Seconds to add to a time in the other file to reach the same moment in the reference.
        public let offset: Double
        public let role: ChannelRole
        /// Pearson correlation at the match, −1…1.
        public let score: Double
        /// How far the match stands out from the next best, 0…1.
        public let prominence: Double

        /// A match good enough to trust: a strong correlation on its own, or a moderate one that
        /// clearly beats every other placement — the rule motion sync uses, since lap after lap of
        /// the same revs makes a placement one lap away score almost as well.
        public var isConfident: Bool { score >= 0.8 || (score >= 0.5 && prominence >= 0.25) }
    }

    /// The roles both sessions recorded, most telling first: what the driver can line them up by.
    public static func sharedRoles(_ reference: TelemetrySession, _ other: TelemetrySession) -> [ChannelRole] {
        let shared = Set(reference.orderedChannels.map(\.role)).intersection(other.orderedChannels.map(\.role))
        let preferred = preferredRoles.filter { shared.contains($0) }
        let rest = reference.orderedChannels.map(\.role).filter { role in
            shared.contains(role) && !preferred.contains(role) && !excluded.contains(role)
        }
        return preferred + rest
    }

    /// What lining up by would mislead: the clock, position, and what the app works out itself.
    static let excluded: Set<ChannelRole> = [
        .time, .latitude, .longitude, .distance, .lap, .lapDelta, .speedDelta, .projectedLap, .gpsRate,
    ]

    /// Where `other` fits against `reference` by `role` (else the first shared role); `nil` when they
    /// share none, or a channel is flat or too short to say.
    public static func align(
        _ other: TelemetrySession, to reference: TelemetrySession, by role: ChannelRole? = nil, rate: Double = 10
    ) -> Result? {
        guard let role = role ?? sharedRoles(reference, other).first, let theirs = other[role],
            let ours = reference[role], let theirsUnit = Optional(theirs.unit)
        else { return nil }
        // The same unit on both sides, so a km/h log and an m/s log compare.
        let converted = theirs.values.map { theirsUnit.convert($0, to: ours.unit) ?? $0 }
        let a = SignalCorrelation.resample(times: theirs.times, values: converted, rate: rate)
        let b = SignalCorrelation.resample(times: ours.times, values: ours.values, rate: rate)
        let shortIsOther = a.values.count <= b.values.count
        let short = SignalCorrelation.normalise(shortIsOther ? a.values : b.values, window: 0)
        let long = SignalCorrelation.normalise(shortIsOther ? b.values : a.values, window: 0)
        guard let found = SignalCorrelation.bestOffset(short: short, long: long, rate: rate, minimumOverlap: 0.5)
        else { return nil }
        // found.offset: short-axis second s ↔ long-axis second s + found.offset, each from its own start.
        let offset =
            shortIsOther
            ? b.start + found.offset - a.start
            : -(a.start + found.offset - b.start)
        return Result(offset: offset, role: role, score: found.score, prominence: found.prominence)
    }
}
