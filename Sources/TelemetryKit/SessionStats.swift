import Foundation

/// The headline numbers of a session, or of one lap of it, for a stat card (#151): what a
/// shareable clip of a track day leads with.
public struct SessionStats: Sendable, Equatable {
    /// A lap and its time.
    public struct LapTime: Sendable, Equatable {
        public let number: Int
        public let seconds: Double
    }

    /// The quickest complete lap of the session.
    public let bestLap: LapTime?
    /// The lap the stats are for, when they are for one lap rather than the session.
    public let lap: LapTime?
    /// Seconds the lap was behind (+) the session's best; zero on the best lap itself.
    public let deltaToBest: Double?
    /// The highest speed, in the speed channel's own unit (m/s), over the session or the lap.
    public let topSpeed: Double?
    /// The best sectors spliced into one lap, when the session has sectors.
    public let optimalLap: Double?
    /// How many complete laps the session has.
    public let completeLaps: Int

    /// The whole session.
    public init(session: TelemetrySession) {
        let complete = session.laps.filter(\.isComplete)
        bestLap = Self.best(of: complete)
        lap = nil
        deltaToBest = nil
        topSpeed = session[.speed]?.maxValue
        optimalLap = session.sectors?.theoreticalLapTime
        completeLaps = complete.count
    }

    /// One lap of the session: its time, its top speed and how it compares with the best.
    public init(lap: Lap, in session: TelemetrySession) {
        let complete = session.laps.filter(\.isComplete)
        let best = Self.best(of: complete)
        bestLap = best
        self.lap = lap.isComplete ? lap.duration.map { LapTime(number: lap.number, seconds: $0) } : nil
        deltaToBest = zip2(self.lap?.seconds, best?.seconds).map { $0 - $1 }
        let end = lap.end ?? session.timeRange?.upperBound ?? lap.start
        topSpeed = session[.speed].flatMap { channel in
            zip(channel.times, channel.values).filter { $0.0 >= lap.start && $0.0 <= end }.map(\.1).max()
        }
        optimalLap = session.sectors?.theoreticalLapTime
        completeLaps = complete.count
    }

    private static func best(of laps: [Lap]) -> LapTime? {
        laps.compactMap { lap in lap.duration.map { LapTime(number: lap.number, seconds: $0) } }
            .min { $0.seconds < $1.seconds }
    }
}

private func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}
