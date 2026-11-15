import Foundation

/// A lap the driver says does not count (#554): driven behind traffic, under a flag, with an off
/// or a cut. It is still timed and listed, but it is never the session's best, never feeds the
/// optimal lap's sectors or the fastest rolling lap, and is left out of the consistency figures,
/// the Trends and the personal bests, because its time says nothing true about how they drive.
///
/// Pinned to a moment inside the lap, in session time, rather than to the lap's number, so the
/// mark stays on the driving it was made for when the laps are read again from a moved line.
public struct LapMark: Sendable, Hashable, Codable, Identifiable {
    public enum Reason: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
        /// Held up by a slower car, or let a faster one by.
        case traffic
        /// A yellow flag, a full-course caution or anything else the circuit imposed.
        case flag
        /// Off the track, or a corner cut: a lap time that was never really driven.
        case offTrack
        /// Anything else the driver does not want counted.
        case other

        public var id: String { rawValue }

        /// The menu's word for it: "Traffic", "Flag", "Off Track", "Other".
        public var title: String {
            switch self {
            case .traffic: "Traffic"
            case .flag: "Flag"
            case .offTrack: "Off Track"
            case .other: "Other"
            }
        }

        /// Lower case, for a sentence or beside a lap time: "traffic", "off track".
        public var word: String { title.lowercased() }
    }

    public var id: UUID
    /// A moment inside the lap, in session time: its middle when it was marked.
    public var time: Double
    public var reason: Reason

    public init(id: UUID = UUID(), time: Double, reason: Reason) {
        self.id = id
        self.time = time
        self.reason = reason
    }

    /// A mark on `lap`, at its middle (its start when it has no end).
    public init(lap: Lap, reason: Reason) {
        self.init(time: lap.end.map { (lap.start + $0) / 2 } ?? lap.start, reason: reason)
    }
}

extension [LapMark] {
    /// The mark on `lap`, if any.
    public func mark(of lap: Lap) -> LapMark? { first { lap.contains($0.time) } }

    /// These marks with `lap` marked for `reason`, or cleared when `reason` is `nil`; at most one
    /// mark per lap.
    public func marking(_ lap: Lap, as reason: LapMark.Reason?) -> [LapMark] {
        var result = filter { !lap.contains($0.time) }
        if let reason { result.append(LapMark(lap: lap, reason: reason)) }
        return result.sorted { $0.time < $1.time }
    }
}

extension TelemetrySession {
    /// The driver's mark on `lap`, if they said it does not count.
    public func lapMark(of lap: Lap) -> LapMark? { lapMarks.mark(of: lap) }

    /// Whether `lap` counts towards the best, the optimal and the consistency: no mark on it.
    public func counts(_ lap: Lap) -> Bool { lapMarks.isEmpty || lapMarks.mark(of: lap) == nil }

    /// The session's sector times without the laps that do not count, so the optimal lap is
    /// spliced only from laps that do. The same as `sectors` with no marks.
    public var countedSectors: SectorAnalysis? {
        guard let sectors, !lapMarks.isEmpty else { return sectors }
        return sectors.counting(in: self)
    }
}

extension SectorAnalysis {
    /// The same layout, with only the laps of `session` that count.
    public func counting(in session: TelemetrySession) -> SectorAnalysis {
        guard !session.lapMarks.isEmpty else { return self }
        let marked = Set(session.laps.filter { !session.counts($0) }.map(\.number))
        return SectorAnalysis(layout: layout, laps: laps.filter { !marked.contains($0.lapNumber) })
    }

    /// The laps the optimal lap is spliced from, in lap order, each once: "laps 4, 6 and 7".
    /// Empty until every sector has been timed.
    public var optimalSources: [Int] {
        let bests = best
        guard !bests.isEmpty, bests.allSatisfy({ $0 != nil }) else { return [] }
        return Set(bests.compactMap { $0?.lapNumber }).sorted()
    }
}

extension [Lap] {
    /// These laps without the ones `session`'s driver marked as not counting.
    public func counting(in session: TelemetrySession) -> [Lap] {
        session.lapMarks.isEmpty ? self : filter { session.counts($0) }
    }
}
