import Foundation
import TelemetryKit

/// What one corner read on a session's best lap (#353), kept with the entry so trends across
/// visits are a read of the logbook, not of every file.
public struct CornerRecord: Hashable, Codable, Sendable {
    public var index: Int
    public var label: String
    /// Metres before the apex; `nil` when the lap never braked for it or nothing said.
    public var brakePointMeters: Double?
    /// m/s.
    public var minimumSpeed: Double
    public var exitSpeed: Double
    public var timeInCorner: Double

    public init(
        index: Int, label: String, brakePointMeters: Double?, minimumSpeed: Double, exitSpeed: Double,
        timeInCorner: Double
    ) {
        self.index = index
        self.label = label
        self.brakePointMeters = brakePointMeters
        self.minimumSpeed = minimumSpeed
        self.exitSpeed = exitSpeed
        self.timeInCorner = timeInCorner
    }
}

extension LogbookEntry {
    /// The corner measurement this build makes; step it when a fix changes what is measured, so
    /// entries read before it are offered a fresh reading (#438). 2: braking that begins after a
    /// corner has ended is the next corner's.
    public static let cornerMeasurement = 2

    /// Whether Trends should offer to read this entry's corners: none kept yet, or kept from a
    /// measurement since corrected.
    public var needsCornerReading: Bool { corners.isEmpty || cornerMeasurement < Self.cornerMeasurement }

    /// Reads the corners of `session`'s best lap into the entry, with this build's measurement.
    public mutating func readCorners(of session: TelemetrySession) {
        corners = Self.cornerRecords(of: session)
        cornerMeasurement = Self.cornerMeasurement
    }

    /// The corners of `session`'s best lap, as the entry keeps them; empty without laps or position.
    public static func cornerRecords(of session: TelemetrySession) -> [CornerRecord] {
        guard let best = LapDeltas.sessionBest(in: session), let profile = LapProfile(lap: best, in: session) else {
            return []
        }
        let corners = CornerDetector.corners(of: profile)
        let metrics = CornerMetrics.measure(corners: corners, of: profile)
        return metrics.enumerated().map { index, metric in
            var label = String(index + 1)
            if index < session.cornerLabels.count, !session.cornerLabels[index].isEmpty {
                label = session.cornerLabels[index]
            }
            return CornerRecord(
                index: index, label: label, brakePointMeters: metric.brakePointMeters,
                minimumSpeed: metric.minimumSpeed, exitSpeed: metric.exitSpeed, timeInCorner: metric.timeInCorner)
        }
    }
}

/// Am I getting quicker, and where (#353): the logbook's sessions at a circuit as points in
/// time, the spread of each session's laps, and each corner across visits.
public enum LogbookTrends {
    public struct Point: Identifiable, Hashable, Sendable {
        public var id: UUID { entryID }
        public var entryID: UUID
        public var date: Date
        public var car: String
        public var best: Double?
        public var optimal: Double?
        public var rolling: Double?
        /// Standard deviation of the flying laps' times, seconds; `nil` under three laps.
        public var spread: Double?
        public var corners: [CornerRecord]
    }

    /// The sessions at `circuitKey` (in `car`, when given), oldest first — by the day they were
    /// driven, or the day they were entered when the file carried no date.
    public static func points(for entries: [LogbookEntry], circuitKey: String, car: String? = nil) -> [Point] {
        // Sessions that name no circuit are not visits to one place (#455).
        guard !circuitKey.isEmpty else { return [] }
        return entries.filter { entry in
            LogbookFilter.circuitKey(of: entry) == circuitKey
                && (car.map { $0.isEmpty || entry.car.caseInsensitiveCompare($0) == .orderedSame } ?? true)
        }
        .sorted { ($0.date ?? $0.added) < ($1.date ?? $1.added) }
        .map { entry in
            Point(
                entryID: entry.id, date: entry.date ?? entry.added, car: entry.car, best: entry.bestLap,
                optimal: entry.optimalLap, rolling: entry.fastestRollingLap, spread: lapSpread(of: entry),
                corners: entry.corners)
        }
    }

    /// How consistent a session was: the standard deviation of its flying laps — complete laps
    /// within `tolerance` of the best — in seconds; `nil` with fewer than three.
    public static func lapSpread(of entry: LogbookEntry, tolerance: Double = 0.10) -> Double? {
        guard let best = entry.bestLap else { return nil }
        let flying = entry.laps.compactMap { lap -> Double? in
            guard lap.isComplete, let seconds = lap.seconds, seconds <= best * (1 + tolerance) else { return nil }
            return seconds
        }
        guard flying.count >= 3 else { return nil }
        let mean = flying.reduce(0, +) / Double(flying.count)
        let variance = flying.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(flying.count - 1)
        return variance.squareRoot()
    }

    /// One corner across visits: the latest session's reading, the one before, and the personal
    /// best session's, matched by the corner's label.
    public struct CornerTrend: Identifiable, Hashable, Sendable {
        public var id: String { label }
        public var label: String
        public var latest: CornerRecord?
        public var previous: CornerRecord?
        public var best: CornerRecord?

        public var brakePointChange: Double? { difference(\.brakePointMeters, latest, previous) }
        public var brakePointToBest: Double? { difference(\.brakePointMeters, latest, best) }
        public var minimumSpeedChange: Double? { difference(\.minimumSpeed, latest, previous) }
        public var minimumSpeedToBest: Double? { difference(\.minimumSpeed, latest, best) }
        public var timeChange: Double? { difference(\.timeInCorner, latest, previous) }
        public var timeToBest: Double? { difference(\.timeInCorner, latest, best) }

        func difference(_ key: KeyPath<CornerRecord, Double?>, _ a: CornerRecord?, _ b: CornerRecord?) -> Double? {
            guard let a = a?[keyPath: key], let b = b?[keyPath: key] else { return nil }
            return a - b
        }

        func difference(_ key: KeyPath<CornerRecord, Double>, _ a: CornerRecord?, _ b: CornerRecord?) -> Double? {
            guard let a, let b else { return nil }
            return a[keyPath: key] - b[keyPath: key]
        }
    }

    /// The corner table's three sessions and its rows (#426). A visit is a track day — the sessions
    /// at the circuit on one calendar day — and stands for the quickest of its sessions with corners
    /// read, so a day of six sessions is compared with the day before, not session with session.
    public struct CornerComparison: Hashable, Sendable {
        /// The best session of the latest track day with corners.
        public var latest: Point
        /// The best session of the track day before it; `nil` with one track day.
        public var previous: Point?
        /// The personal best's session, `nil` when that is `latest`.
        public var best: Point?
        public var trends: [CornerTrend]
    }

    public static func cornerComparison(
        for entries: [LogbookEntry], circuitKey: String, car: String? = nil, calendar: Calendar = .current
    ) -> CornerComparison? {
        let read = points(for: entries, circuitKey: circuitKey, car: car).filter { !$0.corners.isEmpty }
        let days = Dictionary(grouping: read) { calendar.startOfDay(for: $0.date) }.sorted { $0.key < $1.key }
        func quickest(_ points: [Point]) -> Point? { points.min { ($0.best ?? .infinity) < ($1.best ?? .infinity) } }
        guard let latest = days.last.flatMap({ quickest($0.value) }) else { return nil }
        let previous = days.dropLast().last.flatMap { quickest($0.value) }
        let best = quickest(read).flatMap { $0.entryID == latest.entryID ? nil : $0 }
        func record(_ label: String, in point: Point?) -> CornerRecord? { point?.corners.first { $0.label == label } }
        let trends = latest.corners.map { corner in
            CornerTrend(
                label: corner.label, latest: corner, previous: record(corner.label, in: previous),
                best: record(corner.label, in: best))
        }
        return CornerComparison(latest: latest, previous: previous, best: best, trends: trends)
    }

    /// The corners of the latest track day against the one before and the personal best's session.
    public static func cornerTrends(
        for entries: [LogbookEntry], circuitKey: String, car: String? = nil, calendar: Calendar = .current
    ) -> [CornerTrend] {
        cornerComparison(for: entries, circuitKey: circuitKey, car: car, calendar: calendar)?.trends ?? []
    }

    /// A sentence for VoiceOver and the summary line: where the best lap went across the visits.
    /// With several sessions a day it compares the best of the first track day with the best of
    /// the last (#424), so a warm-up session does not set the starting time.
    public static func summary(of points: [Point], calendar: Calendar = .current) -> String {
        let dated = points.filter { $0.best != nil }
        guard let first = dated.first, let last = dated.last, let a = first.best, let b = last.best else {
            return "No complete laps to compare yet."
        }
        guard dated.count > 1 else { return "One visit so far: best \(lapTime(a))." }
        let days = Dictionary(grouping: dated) { calendar.startOfDay(for: $0.date) }.sorted { $0.key < $1.key }
        if days.count == 1 {
            let day = first.date.formatted(.dateTime.day().month(.abbreviated).year())
            return "Best lap \(lapTime(a)) in the first session to \(lapTime(b)) in the last: "
                + "\(change(from: a, to: b)) over \(dated.count) sessions on \(day)."
        }
        if days.count == dated.count {
            return "Best lap \(lapTime(a)) in \(month(first.date)) to \(lapTime(b)) in \(month(last.date)): "
                + "\(change(from: a, to: b)) over \(dated.count) visits."
        }
        let from = days.first?.value.compactMap(\.best).min() ?? a
        let to = days.last?.value.compactMap(\.best).min() ?? b
        return "Best lap \(lapTime(from)) in \(month(first.date)) to \(lapTime(to)) in \(month(last.date)): "
            + "\(change(from: from, to: to)) over \(days.count) days, \(dated.count) sessions."
    }

    static func change(from a: Double, to b: Double) -> String {
        let direction = b < a ? "quicker" : (b > a ? "slower" : "level")
        return "\(direction) by \(String(format: "%.2f", abs(a - b))) s"
    }

    /// Where the trends charts put each session (#424); see `TrendsChartLayout`.
    public static func chartLayout(of points: [Point], calendar: Calendar = .current, dayGap: Double = 1)
        -> TrendsChartLayout
    {
        var positions: [Double] = []
        var days: [TrendsChartLayout.Day] = []
        var next = 0.0
        for point in points {
            let day = calendar.startOfDay(for: point.date)
            if let current = days.last, current.date == day {
                days[days.count - 1].last = next
            } else {
                if !days.isEmpty { next += dayGap }
                days.append(TrendsChartLayout.Day(date: day, first: next, last: next))
            }
            positions.append(next)
            next += 1
        }
        return TrendsChartLayout(positions: positions, days: days)
    }

    public static func lapTime(_ seconds: Double) -> String { TimeParsing.lapTimeString(seconds) }
    public static func month(_ date: Date) -> String { date.formatted(.dateTime.month(.abbreviated).year()) }
}

/// Where the trends charts put each session (#424): one evenly spaced slot per session in date
/// order, a gap of `dayGap` slots between track days, so a day's sessions read as a group and
/// the months between visits take no room.
public struct TrendsChartLayout: Hashable, Sendable {
    public struct Day: Hashable, Sendable {
        /// The start of the day the sessions were driven.
        public var date: Date
        /// The positions of its first and last session.
        public var first: Double
        public var last: Double
        public var center: Double { (first + last) / 2 }
    }

    /// One position per point, in the points' order.
    public var positions: [Double]
    public var days: [Day]

    /// The x domain, half a slot either side of the sessions.
    public var domain: ClosedRange<Double> {
        (positions.first ?? 0) - 0.5...(positions.last ?? 0) + 0.5
    }

    /// Midway between one day's last session and the next day's first: where a rule goes.
    public var boundaries: [Double] {
        zip(days, days.dropFirst()).map { ($0.last + $1.first) / 2 }
    }

    /// The index of the session nearest `x`, for a click on the chart.
    public func nearestIndex(to x: Double) -> Int? {
        positions.indices.min { abs(positions[$0] - x) < abs(positions[$1] - x) }
    }
}
