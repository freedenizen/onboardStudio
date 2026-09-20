/// One lap (or partial lap) within a session, in session time seconds.
public struct Lap: Sendable, Equatable, Codable {
    public let number: Int
    public let start: Double
    public let end: Double?
    /// `false` when the lap's true start or end was not observed (e.g. the recording began
    /// mid-lap or ended before the finish line).
    public let isComplete: Bool

    public init(number: Int, start: Double, end: Double?, isComplete: Bool) {
        self.number = number
        self.start = start
        self.end = end
        self.isComplete = isComplete
    }

    public var duration: Double? {
        guard let end else { return nil }
        return end - start
    }

    public func contains(_ time: Double) -> Bool {
        time >= start && (end.map { time < $0 } ?? true)
    }
}

/// Lap-timing values resolved for a specific moment.
public struct LapTiming: Sendable, Equatable {
    public let currentLap: Lap?
    /// Seconds elapsed since the current lap started.
    public let elapsedInLap: Double?
    public let lastLapTime: Double?
    public let bestLapTime: Double?
    public let bestLapNumber: Int?

    /// Resolves lap timing at `time` from a chronologically ordered lap list.
    public static func resolve(at time: Double, laps: [Lap]) -> LapTiming {
        let current = laps.first { $0.contains(time) }
        let completedBefore = laps.filter { lap in
            lap.isComplete && lap.duration != nil && (lap.end ?? .infinity) <= time
        }
        let last = completedBefore.last
        let best = completedBefore.min { ($0.duration ?? .infinity) < ($1.duration ?? .infinity) }
        return LapTiming(
            currentLap: current,
            elapsedInLap: current.map { time - $0.start },
            lastLapTime: last?.duration,
            bestLapTime: best?.duration,
            bestLapNumber: best?.number
        )
    }
}

extension [Lap] {
    /// The lap `time` falls inside, if any. Laps are contiguous, so the first match wins.
    public func lap(containing time: Double) -> Lap? {
        first { time >= $0.start && time < ($0.end ?? .infinity) }
    }

    /// The next lap to begin strictly after `time`.
    ///
    /// Strictly after, with a tolerance, so jumping repeatedly walks the session instead of
    /// sticking on the lap the playhead was just moved to.
    public func lap(startingAfter time: Double, epsilon: Double = 1e-6) -> Lap? {
        sorted { $0.start < $1.start }.first { $0.start > time + epsilon }
    }

    /// The last lap to begin strictly before `time`.
    ///
    /// Jumping back from the middle of a lap lands on that lap's own start, which is what an
    /// editor's previous-edit behaves like: the first press goes to the start of what you are in.
    public func lap(startingBefore time: Double, epsilon: Double = 1e-6) -> Lap? {
        sorted { $0.start < $1.start }.last { $0.start < time - epsilon }
    }
}
