import Foundation

// What is done with a session's performance runs once they are measured (#553): kept with a
// logbook entry, the best of each measure picked out, and a note on an attempt that should be read
// with care.

extension PerformanceRuns.SpeedRange: CodingKeyRepresentable {}
extension PerformanceRuns.DragDistance: CodingKeyRepresentable {}

extension PerformanceRuns {
    // swiftlint:disable discouraged_optional_boolean
    /// Whether a session is measured: as the driver asked, else when it has no laps and no runs —
    /// a drag strip, a test road. A circuit's pit exit is a standing start too, but a track day is
    /// not measured unless asked.
    public static func isMeasured(asked: Bool?, laps: [Lap]) -> Bool {
        // swiftlint:enable discouraged_optional_boolean
        asked ?? laps.listed.isEmpty
    }
}

extension PerformanceRuns.Result {
    /// Whether there is anything to show.
    public var isEmpty: Bool { attempts.isEmpty && stops.isEmpty }

    /// The quickest of a measure: its seconds, its trap speed where the mark has a trap, and the
    /// attempt it came from.
    public struct Best: Sendable, Equatable {
        public let seconds: Double
        public let trap: Double?
        public let attempt: Int
    }

    /// The quickest time for `range`, and the attempt it came from.
    public func best(_ range: PerformanceRuns.SpeedRange) -> Best? {
        best { $0.speedTimes[range] }.map { Best(seconds: $0.seconds, trap: nil, attempt: $0.attempt) }
    }

    /// The quickest time to `mark`, its trap speed when it has one, and the attempt it came from.
    public func best(_ mark: PerformanceRuns.DragDistance) -> Best? {
        guard let found = best({ $0.distanceTimes[mark] }) else { return nil }
        return Best(seconds: found.seconds, trap: attempts[found.attempt].trapSpeeds[mark], attempt: found.attempt)
    }

    /// The shortest stop from `speed`, and its place among the stops.
    public func best(_ speed: PerformanceRuns.BrakingSpeed) -> (stop: PerformanceRuns.Stop, index: Int)? {
        stops.enumerated().filter { $0.element.from == speed }.min { $0.element.metres < $1.element.metres }
            .map { ($0.element, $0.offset) }
    }

    /// The attempt under way at session `time`, or the stop.
    public func attempt(at time: Double) -> PerformanceRuns.Attempt? {
        attempts.first { $0.start <= time && time <= $0.end }
    }

    public func stop(at time: Double) -> PerformanceRuns.Stop? {
        stops.first { $0.start <= time && time <= $0.end }
    }

    private func best(_ value: (PerformanceRuns.Attempt) -> Double?) -> (seconds: Double, attempt: Int)? {
        attempts.enumerated().compactMap { index, attempt in value(attempt).map { ($0, index) } }
            .min { $0.0 < $1.0 }
            .map { (seconds: $0.0, attempt: $0.1) }
    }
}

extension PerformanceRuns.Attempt {
    /// What to bear in mind about it: "1.8 % downhill: quicker than on the level", "5 Hz: times
    /// ±0.1 s". Empty when nothing needs saying.
    public var notes: [String] {
        var notes: [String] = []
        if let note = PerformanceRuns.slopeNote(slope) { notes.append(note) }
        // Rounded: a 10 Hz log measured over an attempt comes to 9.999… Hz.
        let hertz = sampleHertz.rounded()
        if hertz < PerformanceRuns.Options.notableRate {
            notes.append(String(format: "%.0f Hz: times ±%.1f s", hertz, 1 / max(hertz * 2, 1)))
        }
        return notes
    }
}

extension PerformanceRuns.Stop {
    /// "1.8 % downhill: longer than on the level". Empty when nothing needs saying.
    public var notes: [String] { PerformanceRuns.slopeNote(slope, stopping: true).map { [$0] } ?? [] }
}

extension PerformanceRuns {
    /// "1.8 % downhill: quicker than on the level" over the notable slope, else `nil`. Downhill
    /// helps a launch and lengthens a stop.
    static func slopeNote(_ slope: Double?, stopping: Bool = false) -> String? {
        guard let slope, abs(slope) > Options.notableSlope else { return nil }
        let percent = String(format: "%.1f %%", abs(slope) * 100)
        let helped = (slope < 0) != stopping
        let effect = stopping ? (helped ? "shorter" : "longer") : (helped ? "quicker" : "slower")
        return "\(percent) \(slope > 0 ? "uphill" : "downhill"): \(effect) than on the level"
    }
}
