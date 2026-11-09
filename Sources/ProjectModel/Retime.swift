import Foundation

/// A stretch of the project that plays at another rate, or a moment that holds (#442). Retimes
/// are placed in project time, where everything else on the timeline lives; what they change is
/// how long the finished video takes to show it (`TimeMap`).
public struct Retime: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: Codable, Hashable, Sendable {
        /// Plays `start..<end` at `rate`: 0.5 is half speed, 2 is double.
        case speed(end: Double, rate: Double)
        /// Shows the frame at `start` for `seconds` before playing on.
        case hold(seconds: Double)
    }

    public var id: UUID
    /// Project seconds where it begins.
    public var start: Double
    public var kind: Kind

    public init(id: UUID = UUID(), start: Double, kind: Kind) {
        self.id = id
        self.start = start
        self.kind = kind
    }

    /// The slowest and fastest a stretch may play.
    public static let rates: ClosedRange<Double> = 0.1...8
    /// The longest a hold may last, seconds.
    public static let longestHold = 30.0
}

/// Output time ↔ project time for a list of retimes (#442): piecewise linear, flat where a frame
/// holds. Output time is the finished video's clock; project time is the timeline's, which data,
/// segments, markers and ranges are placed on. The picture is retimed to it and every overlay is
/// drawn at the project time it maps to, so the gauges never part from the picture.
public struct TimeMap: Hashable, Sendable {
    /// One straight piece: output `outputStart..<outputEnd` shows project `projectStart..<projectEnd`.
    /// A hold has `projectStart == projectEnd`.
    public struct Piece: Hashable, Sendable {
        public let outputStart: Double
        public let outputEnd: Double
        public let projectStart: Double
        public let projectEnd: Double

        public var isHold: Bool { projectEnd == projectStart }
        /// Project seconds per output second: 0 for a hold.
        public var rate: Double { (projectEnd - projectStart) / (outputEnd - outputStart) }
        public var isRetimed: Bool { abs(rate - 1) > 1e-9 }
    }

    /// The pieces in time order, tiling `0..<outputDuration` and `0..<projectDuration`.
    public let pieces: [Piece]
    public let projectDuration: Double

    public var outputDuration: Double { pieces.last?.outputEnd ?? projectDuration }
    public var isIdentity: Bool { !pieces.contains(where: \.isRetimed) }

    /// No retimes: output time is project time.
    public static func identity(_ projectDuration: Double) -> TimeMap {
        TimeMap(retimes: [], projectDuration: projectDuration)
    }

    /// The map for `retimes` over a project `projectDuration` long. Retimes outside the project
    /// are dropped; a speed stretch that overlaps an earlier one starts where that one ends; holds
    /// at one moment add up, to `Retime.longestHold` at most; a hold inside a stretch holds there and the stretch plays on after.
    public init(retimes: [Retime], projectDuration: Double) {
        self.projectDuration = max(projectDuration, 0)
        struct Stretch {
            let start: Double
            let end: Double
            let rate: Double
        }
        var stretches: [Stretch] = []
        var holds: [Double: Double] = [:]
        for retime in retimes.sorted(by: { $0.start < $1.start }) {
            switch retime.kind {
            case .speed(let end, let rate):
                let start = max(retime.start, stretches.last?.end ?? 0, 0)
                let end = min(end, self.projectDuration)
                guard end - start > 1e-6, rate.isFinite else { continue }
                let clamped = min(max(rate, Retime.rates.lowerBound), Retime.rates.upperBound)
                stretches.append(Stretch(start: start, end: end, rate: clamped))
            case .hold(let seconds):
                guard retime.start >= 0, retime.start < self.projectDuration, seconds > 0 else { continue }
                holds[retime.start] = min((holds[retime.start] ?? 0) + seconds, Retime.longestHold)
            }
        }
        // Every place the rate can change, and every hold.
        var marks = Set([0, self.projectDuration])
        for stretch in stretches { marks.formUnion([stretch.start, stretch.end]) }
        marks.formUnion(holds.keys)
        let points = marks.sorted()
        var pieces: [Piece] = []
        var output = 0.0
        for (index, point) in points.enumerated() {
            if let seconds = holds[point] {
                pieces.append(
                    Piece(outputStart: output, outputEnd: output + seconds, projectStart: point, projectEnd: point))
                output += seconds
            }
            guard index + 1 < points.count else { break }
            let next = points[index + 1]
            let middle = (point + next) / 2
            let rate = stretches.first { $0.start <= middle && middle < $0.end }?.rate ?? 1
            let length = (next - point) / rate
            pieces.append(Piece(outputStart: output, outputEnd: output + length, projectStart: point, projectEnd: next))
            output += length
        }
        self.pieces = pieces
    }

    /// The project time shown at output time `output`: inside a hold, the held moment.
    public func projectTime(atOutput output: Double) -> Double {
        guard !pieces.isEmpty else { return output }
        if output <= 0 { return 0 }
        guard let piece = pieces.first(where: { output < $0.outputEnd }) else { return projectDuration }
        if piece.isHold { return piece.projectStart }
        return piece.projectStart + (output - piece.outputStart) * piece.rate
    }

    /// The output time at which project time `project` is first shown: for a held moment, the
    /// start of the hold.
    public func outputTime(atProject project: Double) -> Double {
        guard !pieces.isEmpty else { return project }
        if project <= 0 { return 0 }
        guard let piece = pieces.first(where: { project <= $0.projectEnd && (project < $0.projectEnd || $0.isHold) })
        else { return outputDuration }
        if piece.isHold { return piece.outputStart }
        return piece.outputStart + (project - piece.projectStart) / piece.rate
    }

    /// The output stretches that do not play at normal speed, slowed, sped up or held: where the
    /// sound is muted.
    public var retimedOutputRanges: [ClosedRange<Double>] {
        var ranges: [ClosedRange<Double>] = []
        for piece in pieces where piece.isRetimed {
            if let last = ranges.last, abs(last.upperBound - piece.outputStart) < 1e-9 {
                ranges[ranges.count - 1] = last.lowerBound...piece.outputEnd
            } else {
                ranges.append(piece.outputStart...piece.outputEnd)
            }
        }
        return ranges
    }
}

extension Retime {
    /// The speeds the editor offers (#443), slowest first; 1 is normal speed.
    public static let editorRates: [Double] = [0.25, 0.5, 0.75, 1.5, 2]
    /// The hold lengths the editor offers, seconds.
    public static let editorHolds: [Double] = [0.5, 1, 2, 3, 5]

    /// "50%", "200%".
    public static func percent(_ rate: Double) -> String { "\(Int((rate * 100).rounded()))%" }

    /// "Hold 1 s", "Hold 0.5 s".
    public static func holdLabel(_ seconds: Double) -> String {
        "Hold \(seconds.formatted(.number.precision(.fractionLength(0...1)))) s"
    }

    /// Where it ends on the timeline: a hold takes no project time.
    public var end: Double {
        if case .speed(let end, _) = kind { return end }
        return start
    }
}

extension Project {
    /// Plays `range` at `rate` (#443). A speed change that overlaps it is cut back to its edges,
    /// so the range has exactly one speed afterwards; a rate of 1 leaves it at normal speed.
    /// Holds are left as they are.
    public mutating func setSpeed(_ rate: Double, over range: ClosedRange<Double>) {
        var kept: [Retime] = []
        for retime in retimes {
            guard case .speed(let end, let existing) = retime.kind, retime.start < range.upperBound,
                end > range.lowerBound
            else {
                kept.append(retime)
                continue
            }
            // The parts outside the range keep their speed.
            if retime.start < range.lowerBound {
                kept.append(
                    Retime(id: retime.id, start: retime.start, kind: .speed(end: range.lowerBound, rate: existing)))
            }
            if end > range.upperBound {
                kept.append(Retime(start: range.upperBound, kind: .speed(end: end, rate: existing)))
            }
        }
        if abs(rate - 1) > 1e-9, range.upperBound > range.lowerBound {
            kept.append(Retime(start: range.lowerBound, kind: .speed(end: range.upperBound, rate: rate)))
        }
        retimes = kept.sorted { $0.start < $1.start }
    }

    /// Holds the frame at `time` for `seconds`; returns the new hold's id.
    @discardableResult
    public mutating func addHold(at time: Double, seconds: Double) -> UUID {
        let hold = Retime(start: time, kind: .hold(seconds: min(max(seconds, 0.1), Retime.longestHold)))
        retimes.append(hold)
        retimes.sort { $0.start < $1.start }
        return hold.id
    }

    /// A speed change's new rate, or a hold's new length; anything else is left alone.
    public mutating func change(retime id: UUID, rate: Double? = nil, holdSeconds: Double? = nil) {
        guard let index = retimes.firstIndex(where: { $0.id == id }) else { return }
        switch retimes[index].kind {
        case .speed(let end, _):
            if let rate { retimes[index].kind = .speed(end: end, rate: rate) }
        case .hold:
            if let holdSeconds { retimes[index].kind = .hold(seconds: min(max(holdSeconds, 0.1), Retime.longestHold)) }
        }
    }

    public mutating func removeRetime(_ id: UUID) { retimes.removeAll { $0.id == id } }
}
