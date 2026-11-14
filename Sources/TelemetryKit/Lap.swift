/// One lap (or partial lap) within a session, in session time seconds.
///
/// A **run** (#552) is a lap too: from a start line to a different finish line, on an autocross,
/// a hill climb or a stage. Laps cover the session end to end with no gaps (`lap(containing:)`
/// relies on it), so the driving between runs — back to the start, down the hill — is a lap of
/// its own, of kind `transit`: never complete, never numbered for the driver, never listed.
public struct Lap: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        /// A circuit lap, from the start/finish line round to it again.
        case lap
        /// From the start line to the finish line of a point-to-point course. Incomplete when the
        /// finish was never reached: a DNF.
        case run
        /// Driving between runs. Its number is negative so it never collides with a run's.
        case transit
    }

    public let number: Int
    public let start: Double
    public let end: Double?
    /// `false` when the lap's true start or end was not observed (e.g. the recording began
    /// mid-lap or ended before the finish line).
    public let isComplete: Bool
    public let kind: Kind

    public init(number: Int, start: Double, end: Double?, isComplete: Bool, kind: Kind = .lap) {
        self.number = number
        self.start = start
        self.end = end
        self.isComplete = isComplete
        self.kind = kind
    }

    /// The same lap, no longer complete — a pit-lane fragment, or a run that came up short.
    public var demoted: Lap { Lap(number: number, start: start, end: end, isComplete: false, kind: kind) }

    /// Whether the driver sees this lap in a list: every lap and run, never the driving between.
    public var isListed: Bool { kind != .transit }

    /// What the driver calls it, capitalised for a title: "Lap 7", "Run 3".
    public var title: String { "\(kind == .run ? "Run" : "Lap") \(number)" }

    private enum CodingKeys: String, CodingKey { case number, start, end, isComplete, kind }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = try c.decode(Int.self, forKey: .number)
        start = try c.decode(Double.self, forKey: .start)
        end = try c.decodeIfPresent(Double.self, forKey: .end)
        isComplete = try c.decode(Bool.self, forKey: .isComplete)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .lap
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
        // Between runs there is no lap to time, so the driving back to the start reads as none.
        let current = laps.first { $0.isListed && $0.contains(time) }
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
    /// The laps and runs the driver sees, without the driving between runs.
    public var listed: [Lap] { filter(\.isListed) }

    /// Whether these are a point-to-point course's runs rather than a circuit's laps.
    public var areRuns: Bool { contains { $0.kind == .run } }

    /// "Lap" or "Run", for a heading over these.
    public var noun: String { areRuns ? "Run" : "Lap" }

    /// The lap `time` falls inside, if any. Laps are contiguous, so the first match wins.
    public func lap(containing time: Double) -> Lap? {
        first { time >= $0.start && time < ($0.end ?? .infinity) }
    }

    /// The next lap to begin strictly after `time`.
    ///
    /// Strictly after, with a tolerance, so jumping repeatedly walks the session instead of
    /// sticking on the lap the playhead was just moved to.
    public func lap(startingAfter time: Double, epsilon: Double = 1e-6) -> Lap? {
        listed.sorted { $0.start < $1.start }.first { $0.start > time + epsilon }
    }

    /// The last lap to begin strictly before `time`.
    ///
    /// Jumping back from the middle of a lap lands on that lap's own start, which is what an
    /// editor's previous-edit behaves like: the first press goes to the start of what you are in.
    public func lap(startingBefore time: Double, epsilon: Double = 1e-6) -> Lap? {
        listed.sorted { $0.start < $1.start }.last { $0.start < time - epsilon }
    }
}
