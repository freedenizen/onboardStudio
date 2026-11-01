import Foundation

extension LapProfile {
    /// A stretch of one lap to splice into a profile: from `from` to `to` metres into `lap`.
    public struct Cut: Sendable, Equatable {
        public let lap: Lap
        public let from: Double
        public let to: Double

        public init(lap: Lap, from: Double, to: Double) {
            self.lap = lap
            self.from = from
            self.to = to
        }

        public var length: Double { max(0, to - from) }
    }

    /// Stretches of several laps joined end to end into one profile, each starting where the one
    /// before ends. What a rolling lap re-based to the start/finish line and an optimal lap
    /// assembled from the best sectors both are.
    ///
    /// Elapsed time runs on across the joins, so the profile's duration is the cuts' times added
    /// together. Speed and the pedals are each lap's own, so they can step at a join; `seams`
    /// says where, and anything reading a corner that straddles one should say so.
    public static func spliced(
        _ cuts: [Cut], in session: TelemetrySession, label: String, stepMeters: Double = 2,
        roles: [ChannelRole] = LapProfile.defaultRoles, smoothingMeters: Double = 25
    ) -> LapProfile? {
        let step = max(0.5, stepMeters)
        guard let distance = session[.distance], !cuts.isEmpty, cuts.allSatisfy({ $0.lap.end != nil }) else {
            return nil
        }
        var distances: [Double] = []
        var times: [Double] = []
        var elapsed: [Double] = []
        var pieces: [Piece] = []
        var offset = 0.0
        var clock = 0.0
        for cut in cuts {
            guard let end = cut.lap.end, cut.length > 0, let lapStart = distance.value(at: cut.lap.start) else {
                continue
            }
            func time(at into: Double) -> Double {
                LapComparison.time(atDistance: lapStart + into, in: distance, between: cut.lap.start, and: end) ?? end
            }
            let startTime = time(at: cut.from)
            let endTime = max(startTime, time(at: cut.to))
            // Grid points of the whole profile that fall in this cut, so the grid stays uniform
            // across the joins.
            var gridDistance = (offset / step).rounded(.up) * step
            if gridDistance < offset + 1e-9 { gridDistance = offset }
            while gridDistance < offset + cut.length - 1e-6 {
                let at = max(startTime, min(time(at: cut.from + (gridDistance - offset)), endTime))
                distances.append(gridDistance)
                times.append(at)
                elapsed.append(clock + at - startTime)
                gridDistance += step
            }
            pieces.append(Piece(lapNumber: cut.lap.number, range: offset...(offset + cut.length)))
            offset += cut.length
            clock += endTime - startTime
        }
        guard distances.count >= 4, let lastCut = cuts.last, let lastEnd = lastCut.lap.end else { return nil }
        distances.append(offset)
        times.append(min(lastEnd, times.last ?? lastEnd))
        elapsed.append(clock)
        for index in 1..<elapsed.count where elapsed[index] < elapsed[index - 1] { elapsed[index] = elapsed[index - 1] }
        // The last grid time is the last cut's end, which `time(at:)` clamps to the lap's end.
        if let end = lastCut.lap.end, let start = distance.value(at: lastCut.lap.start) {
            times[times.count - 1] =
                LapComparison.time(atDistance: start + lastCut.to, in: distance, between: lastCut.lap.start, and: end)
                ?? end
        }
        let window = Window(start: cuts[0].lap.start, end: lastEnd)
        return LapProfile(
            window: window, label: label, stepMeters: step, distances: distances, times: times, elapsed: elapsed,
            pieces: pieces, session: session, roles: roles, smoothingMeters: smoothingMeters)
    }
}
