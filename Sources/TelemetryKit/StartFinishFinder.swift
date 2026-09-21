import Foundation

/// Proposes a start/finish line from the data, so a session opens with something workable and the
/// driver corrects it rather than authoring it from coordinates.
///
/// Two routes, in order of how much they know:
///
/// 1. **The file's own laps.** A logger that records a lap number already knows where the line is
///    — it is wherever lap 2 began. Nothing needs deriving.
/// 2. **The trace.** Otherwise, try points around the circuit and keep the one whose laps come out
///    most consistent. A start/finish is only a place the car passes once a lap going the same
///    way, and the trace is full of candidates.
public enum StartFinishFinder {
    /// Where a suggestion came from, which is worth telling the driver: a line read off the
    /// logger's own lap numbers deserves more trust than one derived from the shape of the trace.
    public enum Source: String, Sendable {
        /// Read off the lap numbers the logger recorded.
        case fileLaps
        /// Derived from where the trace repeats.
        case trace
    }

    public struct Suggestion: Sendable, Equatable {
        public let line: FinishLine
        public let source: Source
        /// Complete laps this line produces.
        public let laps: Int
        /// How much the lap *distances* vary, as a fraction of the median. A real start/finish
        /// gives every lap the same length; a line the car crosses twice, or misses on a wide
        /// lap, does not.
        public let spread: Double

        public init(line: FinishLine, source: Source, laps: Int, spread: Double) {
            self.line = line
            self.source = source
            self.laps = laps
            self.spread = spread
        }
    }

    /// Candidate positions tried when the file has no laps of its own. Forty is enough to land on
    /// a straight somewhere on any circuit, and costs one pass over the trace each.
    static let candidateCount = 40
    /// A candidate slower than this fraction of the session's top speed is skipped, which throws
    /// out the pit lane, the paddock and the moments the car was parked.
    static let minimumSpeedFraction = 0.4
    /// Below this many laps there is nothing to be consistent about.
    static let minimumLaps = 2

    /// The best line this session suggests, or `nil` when it has no position or nothing works.
    public static func suggest(in session: TelemetrySession) -> Suggestion? {
        fromFileLaps(session) ?? fromTrace(session)
    }

    // MARK: - The file already knows

    /// The line implied by the lap numbers the logger recorded: where the first complete lap
    /// began. `nil` when the file has no laps, or has only the one the recording started inside.
    static func fromFileLaps(_ session: TelemetrySession) -> Suggestion? {
        let complete = session.laps.filter { $0.isComplete && $0.end != nil }
        guard complete.count >= minimumLaps, let first = complete.first,
            let line = LapDetector.finishLine(at: first.start, in: session)
        else { return nil }
        return score(line, in: session, source: .fileLaps)
    }

    // MARK: - Derived from the trace

    static func fromTrace(_ session: TelemetrySession) -> Suggestion? {
        guard let latitude = session[.latitude], latitude.count > 2, let range = session.timeRange,
            range.upperBound > range.lowerBound
        else { return nil }
        let speed = session[.speed]
        let topSpeed = speed?.maxValue ?? 0
        var best: Suggestion?
        for index in 0..<candidateCount {
            let fraction = (Double(index) + 0.5) / Double(candidateCount)
            let time = range.lowerBound + (range.upperBound - range.lowerBound) * fraction
            // A line where the car was crawling is a line in the pit lane.
            if topSpeed > 0, let here = speed?.value(at: time), here < topSpeed * minimumSpeedFraction { continue }
            guard let line = LapDetector.finishLine(at: time, in: session),
                let candidate = score(
                    line, in: session, source: .trace)
            else { continue }
            if isBetter(candidate, than: best) { best = candidate }
        }
        return best
    }

    /// Prefers the more consistent lap lengths; a candidate that finds more laps only wins when
    /// it is at least as consistent, so a line crossed twice a lap cannot buy its way in on count.
    static func isBetter(_ candidate: Suggestion, than current: Suggestion?) -> Bool {
        guard let current else { return true }
        if abs(candidate.spread - current.spread) > 0.01 { return candidate.spread < current.spread }
        return candidate.laps > current.laps
    }

    // MARK: - Scoring

    /// Runs `line` over the session and reports what it produced, or `nil` when it produces too
    /// few laps to judge.
    static func score(_ line: FinishLine, in session: TelemetrySession, source: Source) -> Suggestion? {
        let laps = LapDetector.detect(in: session, line: line)
        let complete = laps.filter { $0.isComplete && $0.duration != nil }
        guard complete.count >= minimumLaps else { return nil }
        return Suggestion(line: line, source: source, laps: complete.count, spread: spread(of: complete, in: session))
    }

    /// Spread of the complete laps' distances as a fraction of the median, falling back to their
    /// times when the session has no distance channel.
    static func spread(of laps: [Lap], in session: TelemetrySession) -> Double {
        var lengths: [Double] = []
        if let distance = session[.distance] {
            lengths = laps.compactMap { LapComparison.length(of: $0, distance: distance) }
        }
        if lengths.count != laps.count { lengths = laps.compactMap(\.duration) }
        let sorted = lengths.sorted()
        guard let low = sorted.first, let high = sorted.last, sorted.count >= 2 else { return .infinity }
        let median = sorted[sorted.count / 2]
        guard median > 0 else { return .infinity }
        return (high - low) / median
    }
}
