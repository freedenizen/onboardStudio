import Foundation

/// Finds the runs of a point-to-point course (#552): an autocross, a hill climb, a stage. A run
/// starts where the car crosses the start line and ends where it crosses a *different* finish
/// line; a circuit lap is `LapDetector`'s.
///
/// **Stops separate runs.** Every one of these disciplines stages the car at the start and slows
/// it down after the finish, so the session is cut wherever the car stood still, and each moving
/// stretch holds at most one run: from its first crossing of the start to its **last** crossing of
/// the finish. Taking the last, not the first, is what lets an autocross course pass through the
/// finish area mid-run without ending the run there; it is why the stops are used at all, rather
/// than pairing each start with the next finish. Both lines are crossed one way only (their
/// heading), so a hill climb's drive back down crosses neither.
///
/// A stretch that crossed the start and never the finish is a **DNF**: a run, incomplete, ending
/// where the car next stopped. The driving before, between and after the runs is kept as laps of
/// kind `transit`, numbered −1, −2, … so laps still cover the session end to end.
public enum RunDetector {
    public struct Options: Sendable, Equatable {
        /// Below this the car counts as stopped (m/s). Staging creeps forward at walking pace.
        public var stopSpeed: Double
        /// …for at least this long (s). A moment's pause on course is not the end of a run.
        public var stopSeconds: Double

        public init(stopSpeed: Double = 3, stopSeconds: Double = 2) {
            self.stopSpeed = stopSpeed
            self.stopSeconds = stopSeconds
        }
    }

    /// The session's runs and the transit between them, or `[]` without a position trace.
    public static func detect(
        in session: TelemetrySession, start: FinishLine, finish: FinishLine, options: Options = Options()
    ) -> [Lap] {
        guard let lat = session[.latitude], let lon = session[.longitude], let range = session.timeRange else {
            return []
        }
        let starts = crossings(of: start, latitude: lat, longitude: lon)
        let finishes = crossings(of: finish, latitude: lat, longitude: lon)
        let moving = movingStretches(speed: session[.speed], in: range, options: options)
        return runs(starts: starts, finishes: finishes, moving: moving, session: range)
    }

    /// When each line was crossed the way the course runs.
    ///
    /// A line with no heading — a VBO gate says where it is, not which way it is crossed — takes
    /// the direction the car first crossed it in. Without that, a hill climb's drive back down
    /// would cross the finish and then the start, and become a run of its own. The first crossing
    /// of each line is the first run's, because a car is staged below the start before it runs.
    static func crossings(of line: FinishLine, latitude: Channel, longitude: Channel) -> [Double] {
        let found = LapDetector.crossings(latitude: latitude, longitude: longitude, line: line)
        guard line.headingDegrees == nil, let first = found.first else { return found.map(\.time) }
        var directed = line
        directed.headingDegrees = first.headingDegrees
        return LapDetector.crossings(latitude: latitude, longitude: longitude, line: directed).map(\.time)
    }

    /// Runs from crossing times and the stretches the car was moving: see the type's comment.
    public static func runs(
        starts: [Double], finishes: [Double], moving: [ClosedRange<Double>], session: ClosedRange<Double>
    ) -> [Lap] {
        var found: [Lap] = []
        for stretch in moving {
            guard let begin = starts.first(where: { stretch.contains($0) }) else { continue }
            let end = finishes.last { $0 > begin && $0 <= stretch.upperBound }
            found.append(
                Lap(
                    number: found.count + 1, start: begin, end: end ?? stretch.upperBound, isComplete: end != nil,
                    kind: .run))
        }
        var laps: [Lap] = []
        var cursor = session.lowerBound
        var transit = 0
        func addTransit(until time: Double) {
            guard time > cursor else { return }
            transit -= 1
            laps.append(Lap(number: transit, start: cursor, end: time, isComplete: false, kind: .transit))
        }
        for run in found {
            addTransit(until: run.start)
            laps.append(run)
            cursor = run.end ?? cursor
        }
        addTransit(until: session.upperBound)
        return found.isEmpty ? [] : laps
    }

    /// The stretches between stops. Without a speed channel the car is taken to have moved
    /// throughout, which leaves one stretch and at most one run.
    static func movingStretches(speed: Channel?, in range: ClosedRange<Double>, options: Options)
        -> [ClosedRange<Double>]
    {
        guard let speed, speed.count > 1 else { return [range] }
        var stretches: [ClosedRange<Double>] = []
        var movingSince: Double? = range.lowerBound
        var stoppedSince: Double?
        var previous = range.lowerBound
        for (time, value) in zip(speed.times, speed.values) {
            if value < options.stopSpeed {
                if stoppedSince == nil { stoppedSince = time }
                if let since = stoppedSince, time - since >= options.stopSeconds, let began = movingSince {
                    if since > began { stretches.append(began...since) }
                    movingSince = nil
                }
            } else {
                // From the last moment standing: a start line drawn where the car was staged is
                // crossed between that sample and this one, and belongs to this stretch.
                if movingSince == nil { movingSince = previous }
                stoppedSince = nil
            }
            previous = time
        }
        if let began = movingSince, range.upperBound > began { stretches.append(began...range.upperBound) }
        return stretches
    }
}
