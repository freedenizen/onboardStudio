import Foundation

/// A stretch of a session the driver did not drive as they chose (#571): held up by another car,
/// or under a flag. Coaching leaves the corners it covers out of the opportunities and out of the
/// consistency figures, because what the driver did there says nothing about how they drive.
///
/// In session time, the data file's own timebase, so a mark stays on its stretch when the file is
/// trimmed or its laps are found again.
public struct TrafficSpan: Sendable, Hashable, Codable, Identifiable {
    public enum Kind: String, Sendable, Hashable, Codable, CaseIterable {
        /// Behind a slower car, or letting a faster one by.
        case traffic
        /// A yellow flag, a full-course caution or anything else the circuit imposed.
        case flag

        /// "held up by traffic", "under a flag".
        public var phrase: String {
            switch self {
            case .traffic: "held up by traffic"
            case .flag: "under a flag"
            }
        }
    }

    public var id: UUID
    public var start: Double
    public var end: Double
    public var kind: Kind

    public init(id: UUID = UUID(), start: Double, end: Double, kind: Kind = .traffic) {
        self.id = id
        self.start = min(start, end)
        self.end = max(start, end)
        self.kind = kind
    }

    /// Whether the span and `start...end` share any moment.
    public func overlaps(_ start: Double, _ end: Double) -> Bool { self.start <= end && start <= self.end }

    /// "held up by traffic", "under a flag": how the notes say what happened.
    public var phrase: String { kind.phrase }
}

/// A corner that a traffic mark covers, on the lap being read, on the reference, or on both.
public struct CornerTraffic: Sendable, Hashable, Codable {
    public let kind: TrafficSpan.Kind
    public let onLap: Bool
    public let onReference: Bool

    public init(kind: TrafficSpan.Kind, onLap: Bool, onReference: Bool) {
        self.kind = kind
        self.onLap = onLap
        self.onReference = onReference
    }

    /// The table's word for it, in place of the phase: "traffic", "flag".
    public var word: String { kind.rawValue }
}

extension LapProfile {
    /// The mark covering the most of the profile between `from` and `to` metres in, when it
    /// covers at least `minimumFraction` of it; read at each grid point's session time, so a
    /// spliced profile is read lap by lap across its seams. The fraction keeps a mark on one
    /// corner off the next, whose stretch begins where the first one's ends.
    public func traffic(
        from: Double, to: Double, in spans: [TrafficSpan], minimumFraction: Double = 0.25
    ) -> TrafficSpan? {
        guard !spans.isEmpty, count >= 2, times.count == count, to > from else { return nil }
        let first = max(0, min(count - 1, Int((from / stepMeters).rounded(.up))))
        let last = max(first, min(count - 1, Int((to / stepMeters).rounded(.down))))
        var covered: [UUID: Int] = [:]
        for index in first...last {
            let time = times[index]
            if let span = spans.first(where: { $0.start <= time && time <= $0.end }) {
                covered[span.id, default: 0] += 1
            }
        }
        let points = Double(last - first + 1)
        guard let most = covered.max(by: { $0.value < $1.value }), Double(most.value) / points >= minimumFraction
        else { return nil }
        return spans.first { $0.id == most.key }
    }

    /// The session time at which the profile was `distance` metres in, through the lap it was cut
    /// from: for a plain lap the same as `time(atDistance:)`.
    public func sessionTime(atDistance distance: Double) -> Double {
        let segment = segment(at: distance)
        guard times.count == count, count >= 2 else { return time(atDistance: distance) }
        return times[segment.lower] + (times[segment.upper] - times[segment.lower]) * segment.fraction
    }
}

extension TelemetrySession {
    /// Whether no traffic mark touches `lap`.
    public func isClearOfTraffic(_ lap: Lap) -> Bool {
        let end = lap.end ?? .infinity
        return !traffic.contains { $0.overlaps(lap.start, end) }
    }
}

extension [TrafficSpan] {
    /// These marks with `start...end` marked as `kind`, or cleared when `kind` is `nil`: a mark
    /// the stretch cuts through keeps what lies either side of it.
    public func marking(_ start: Double, _ end: Double, as kind: TrafficSpan.Kind?) -> [TrafficSpan] {
        var result: [TrafficSpan] = []
        for span in self {
            guard span.start < end, start < span.end else {
                result.append(span)
                continue
            }
            if span.start < start - 0.05 {
                result.append(TrafficSpan(start: span.start, end: start, kind: span.kind))
            }
            if span.end > end + 0.05 {
                result.append(TrafficSpan(start: end, end: span.end, kind: span.kind))
            }
        }
        if let kind { result.append(TrafficSpan(start: start, end: end, kind: kind)) }
        return result.sorted { $0.start < $1.start }
    }
}

extension [Lap] {
    /// The quickest of these laps other than lap `excluded`, preferring one no traffic mark
    /// touches (#571): a lap that was held up is a poor lap to coach by default.
    public func quickest(excluding excluded: Int?, in session: TelemetrySession) -> Lap? {
        let byTime = filter { $0.number != excluded }.sorted { ($0.duration ?? .infinity) < ($1.duration ?? .infinity) }
        return byTime.first { session.isClearOfTraffic($0) } ?? byTime.first
    }
}

extension CornerComparison {
    /// What a card or note says for a corner a mark covers, instead of a note on the driving:
    /// "Turn 7: held up by traffic", "Turn 7: your best lap was under a flag". `nil` for a corner
    /// no mark covers.
    public func trafficHeadline(referencePhrase: String) -> String? {
        guard let traffic else { return nil }
        if traffic.onLap { return "Turn \(label): \(traffic.kind.phrase)" }
        return "Turn \(label): \(referencePhrase) was \(traffic.kind.phrase)"
    }
}
