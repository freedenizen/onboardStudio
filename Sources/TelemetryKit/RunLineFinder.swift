import Foundation

/// Proposes the start and the finish of a point-to-point course from the driving (#552), so a
/// session of runs opens with lines to correct rather than to place from nothing.
///
/// - **The start** is where runs set off from a standstill: the car stood still, then was at
///   speed within a few seconds without stopping again. Rolling from the grid to the line is a
///   standstill too, but never quick, so it is not taken for a launch. The launches that lie
///   together are the start; the line goes through them, across the way they set off.
/// - **The finish** is where each launch's run stopped being driven: the last moment, before the
///   car next stood still, that it was still at half its top speed of that run. The ends that lie
///   together are the finish — a run that went off course somewhere else is left out.
///
/// Both are a few metres off the real lines at best: the start is where the car first moved,
/// and the finish where it began to slow. They are offered to be checked, and say so.
public enum RunLineFinder {
    public struct Suggestion: Sendable, Equatable {
        public let start: FinishLine
        public let finish: FinishLine
        /// Runs these lines find, and how many of them reached the finish.
        public let runs: Int
        public let finished: Int

        /// "Suggested a start where 3 runs set off and a finish where 2 of them ended."
        public var summary: String {
            let set = runs == 1 ? "1 run sets off" : "\(runs) runs set off"
            let ended = finished == runs ? (runs == 1 ? "it ended" : "they ended") : "\(finished) of them ended"
            return "Suggested a start where \(set) and a finish where \(ended); check both on the map."
        }
    }

    public struct Options: Sendable, Equatable {
        /// Below this the car is standing still (m/s).
        public var standstill: Double = 1.5
        /// A launch reaches this (m/s, about 30 km/h)…
        public var launchSpeed: Double = 8
        /// …within this many seconds of moving off.
        public var launchSeconds: Double = 8
        /// A run is over once it falls below this fraction of its top speed for good.
        public var endFraction: Double = 0.5
        /// Launches, or ends, this close are the same line (m).
        public var clusterMeters: Double = 25

        public init() {}
    }

    /// The suggested lines, or `nil` when the session has no position or speed, or no launch, or
    /// when the lines it suggests time no finished run.
    public static func suggest(in session: TelemetrySession, options: Options = Options()) -> Suggestion? {
        guard let lat = session[.latitude], let lon = session[.longitude], let speed = session[.speed],
            speed.count > 2
        else { return nil }
        let sampler = TelemetrySampler(session: session)
        func mark(_ time: Double) -> Mark? {
            let sample = sampler.sample(at: time)
            guard let latitude = lat.value(at: time), let longitude = lon.value(at: time) else { return nil }
            return Mark(latitude: latitude, longitude: longitude, heading: sample[.heading])
        }
        var launches: [Mark] = []
        var ends: [Mark] = []
        for run in launchWindows(speed: speed, options: options) {
            if let launch = mark(run.launch) { launches.append(launch) }
            if let end = run.end, let point = mark(end) { ends.append(point) }
        }
        guard let start = densest(launches, within: options.clusterMeters),
            let finish = densest(ends, within: options.clusterMeters)
        else { return nil }
        let startLine = start.line()
        let finishLine = finish.line()
        let found = RunDetector.detect(in: session, start: startLine, finish: finishLine).listed
        let finished = found.filter(\.isComplete).count
        guard finished > 0 else { return nil }
        return Suggestion(start: startLine, finish: finishLine, runs: found.count, finished: finished)
    }

    /// Each launch: when the car first moved off from standing still towards a quick run, and
    /// when that run was last at `endFraction` of its top speed before the car stood still again.
    static func launchWindows(speed: Channel, options: Options) -> [(launch: Double, end: Double?)] {
        let times = speed.times
        let values = speed.values
        var windows: [(launch: Double, end: Double?)] = []
        var index = 0
        while index < values.count {
            // Standing still, then the first sample moving.
            guard values[index] < options.standstill else {
                index += 1
                continue
            }
            var move = index
            while move < values.count, values[move] < options.standstill { move += 1 }
            guard move < values.count else { break }
            // Quick enough, soon enough, without stopping again?
            var quick = move
            while quick < values.count, values[quick] < options.launchSpeed, values[quick] >= options.standstill,
                times[quick] - times[move] <= options.launchSeconds
            {
                quick += 1
            }
            guard quick < values.count, values[quick] >= options.launchSpeed else {
                index = move + 1
                continue
            }
            // The run lasts until the car stands still again.
            var stop = quick
            while stop < values.count, values[stop] >= options.standstill { stop += 1 }
            let top = values[move..<stop].max() ?? 0
            let atSpeed = (move..<stop).last { values[$0] >= top * options.endFraction }
            // A sample before the last at speed, so the car crosses the line rather than ending on it.
            let end = atSpeed.map { times[max(move, $0 - 1)] }
            windows.append((times[move], end))
            index = stop
        }
        return windows
    }

    /// A place, and the way the car was going there.
    struct Mark {
        let latitude: Double
        let longitude: Double
        let heading: Double?

        func metres(to other: Mark) -> Double {
            let north = (latitude - other.latitude) * 110_540
            let east = (longitude - other.longitude) * 111_320 * cos(latitude * .pi / 180)
            return (north * north + east * east).squareRoot()
        }

        func line() -> FinishLine {
            FinishLine(latitude: latitude, longitude: longitude, headingDegrees: heading, halfWidthMeters: 15)
        }
    }

    /// The centre of the largest group of `marks` within `metres` of one of them, with the mean of
    /// their headings; ties go to the first.
    static func densest(_ marks: [Mark], within metres: Double) -> Mark? {
        var best: [Mark] = []
        for mark in marks {
            let near = marks.filter { $0.metres(to: mark) <= metres }
            if near.count > best.count { best = near }
        }
        guard !best.isEmpty else { return nil }
        let count = Double(best.count)
        let headings = best.compactMap(\.heading)
        var heading: Double?
        if !headings.isEmpty {
            let x = headings.reduce(0) { $0 + sin($1 * .pi / 180) }
            let y = headings.reduce(0) { $0 + cos($1 * .pi / 180) }
            heading = (atan2(x, y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        }
        return Mark(
            latitude: best.reduce(0) { $0 + $1.latitude } / count,
            longitude: best.reduce(0) { $0 + $1.longitude } / count, heading: heading)
    }
}
