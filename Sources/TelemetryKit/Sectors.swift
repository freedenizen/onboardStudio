import Foundation

/// How a lap is divided into sectors.
///
/// No open data source publishes sector geometry under a licence this project can use, and no
/// logger file surveyed carries it either (see `docs/tracks-and-sectors.md`), so sectors are
/// derived from the driving or drawn by the driver. None of these modes knows anything about the
/// circuit, which is what lets them work on an unmapped venue, an autocross or a hill climb.
public enum SectorMode: Sendable, Hashable {
    /// Split the reference lap's distance into `count` equal parts. The default, because it is
    /// the only mode guaranteed to produce an answer: sector times only have to be *consistent*
    /// lap to lap to say where the time went.
    case equalDistance(count: Int)
    /// `count` sectors, with each boundary moved onto the straight nearest to where an equal
    /// split would have put it, so a sector never cuts a corner in half.
    case cornerAware(count: Int)
    /// Gate lines placed by the driver, in the order the track runs them.
    case manual(lines: [FinishLine])

    public static let defaultCount = 3

    /// Sectors this mode asks for, before the data has a say.
    public var requestedCount: Int {
        switch self {
        case .equalDistance(let count), .cornerAware(let count): max(1, count)
        case .manual(let lines): lines.count + 1
        }
    }
}

/// Where a lap's sectors begin and end, measured once on a reference lap and then applied to
/// every lap by distance travelled.
///
/// Distance rather than geometry deliberately: a gate the car drove around on one wide lap would
/// otherwise lose that lap's sector entirely, and the modes that have no gates need a distance
/// answer anyway. A manual line is resolved to the distance at which the reference lap crossed it.
public struct SectorLayout: Sendable, Equatable {
    /// Distance into the lap of each boundary, ascending and strictly inside the lap. The lap
    /// start and the finish line are not boundaries; they bracket the first and last sector.
    public let boundaryDistances: [Double]
    public let lapLengthMeters: Double
    /// The lap the boundaries were measured on.
    public let referenceLapNumber: Int

    public init(boundaryDistances: [Double], lapLengthMeters: Double, referenceLapNumber: Int) {
        self.boundaryDistances = boundaryDistances
        self.lapLengthMeters = lapLengthMeters
        self.referenceLapNumber = referenceLapNumber
    }

    public var count: Int { boundaryDistances.count + 1 }

    /// The 0-based sector containing `distance` metres into a lap. A car past the last boundary
    /// — including one driving a longer lap than the reference — is in the final sector.
    public func sector(atDistanceIntoLap distance: Double) -> Int {
        var index = 0
        while index < boundaryDistances.count, distance >= boundaryDistances[index] { index += 1 }
        return index
    }

    /// Start and end distance of sector `index` in metres into the lap.
    public func range(of index: Int) -> ClosedRange<Double> {
        let lower = index == 0 ? 0 : boundaryDistances[index - 1]
        let upper = index < boundaryDistances.count ? boundaryDistances[index] : lapLengthMeters
        return lower...max(lower, upper)
    }

    /// `S1`, `S2`, … — what every timing screen calls them.
    public static func name(of index: Int) -> String { "S\(index + 1)" }
}

/// One lap's sector times.
public struct LapSectors: Sendable, Equatable {
    public let lapNumber: Int
    /// Seconds spent in each sector; `nil` where the lap never reached that boundary, which is
    /// what an out-lap, an in-lap and the lap the recording stopped during all look like.
    public let times: [Double?]

    public init(lapNumber: Int, times: [Double?]) {
        self.lapNumber = lapNumber
        self.times = times
    }

    /// The lap time as the sectors add up to it, or `nil` when a sector is missing.
    public var total: Double? {
        var sum = 0.0
        for time in times {
            guard let time else { return nil }
            sum += time
        }
        return sum
    }
}

/// Sector times for a whole session, and what they add up to.
public struct SectorAnalysis: Sendable, Equatable {
    public struct Best: Sendable, Equatable {
        public let time: Double
        public let lapNumber: Int
    }

    public let layout: SectorLayout
    /// Every lap that has at least one timed sector, in lap order.
    public let laps: [LapSectors]

    public init(layout: SectorLayout, laps: [LapSectors]) {
        self.layout = layout
        self.laps = laps
    }

    public var count: Int { layout.count }

    /// The fastest time recorded in each sector, with the lap it came from.
    public var best: [Best?] {
        (0..<count).map { index in
            laps.compactMap { lap in lap.times[index].map { Best(time: $0, lapNumber: lap.lapNumber) } }
                .min { $0.time < $1.time }
        }
    }

    /// Every sector's best time added together: the lap the driver has already shown they can
    /// do, even if they have never put it together. `nil` until every sector has been timed once.
    public var theoreticalLapTime: Double? {
        let bests = best
        guard bests.allSatisfy({ $0 != nil }) else { return nil }
        return bests.compactMap { $0?.time }.reduce(0, +)
    }

    public func sectors(ofLap number: Int) -> LapSectors? { laps.first { $0.lapNumber == number } }

    /// Lap `number`'s sector times, all `nil` when that lap timed none.
    public func times(ofLap number: Int?) -> [Double?] {
        guard let number, let lap = sectors(ofLap: number) else { return [Double?](repeating: nil, count: count) }
        return lap.times
    }

    /// The fastest time recorded in each sector, without the lap it came from.
    public var bestTimes: [Double?] { best.map { $0?.time } }

    /// Lap `number`'s time in `sector` minus the fastest anyone did it this session.
    /// Zero on the lap that set the best.
    public func deltaToBest(sector: Int, lapNumber: Int) -> Double? {
        guard sector >= 0, sector < count, let time = sectors(ofLap: lapNumber)?.times[sector],
            let best = best[sector]
        else { return nil }
        return time - best.time
    }
}

/// Where the car is in the current lap's sectors, for a live readout.
public struct SectorStatus: Sendable, Equatable {
    public let lapNumber: Int
    /// 0-based sector the car is in.
    public let sectorIndex: Int
    /// Seconds since that sector began.
    public let elapsedInSector: Double
    /// This lap's finished sectors; `nil` for the one in progress and the ones still to come.
    public let times: [Double?]

    public init(lapNumber: Int, sectorIndex: Int, elapsedInSector: Double, times: [Double?]) {
        self.lapNumber = lapNumber
        self.sectorIndex = sectorIndex
        self.elapsedInSector = elapsedInSector
        self.times = times
    }
}

/// Builds sector layouts and times. A sector time is the gap between two distances into the lap,
/// which `LapComparison` already knows how to find — this is mostly deciding where to put the
/// boundaries.
public enum Sectors {
    /// The lap sectors are measured on: the session's quickest full lap, falling back to the
    /// longest complete one when nothing has been timed yet.
    public static func referenceLap(in session: TelemetrySession) -> Lap? {
        if let best = LapDeltas.sessionBest(in: session) { return best }
        guard let distance = session[.distance] else { return nil }
        return session.laps.filter { $0.isComplete && $0.end != nil }
            .max {
                (LapComparison.length(of: $0, distance: distance) ?? 0)
                    < (LapComparison.length(of: $1, distance: distance) ?? 0)
            }
    }

    /// Where `mode` puts the boundaries. `nil` when the session has no laps or no distance
    /// channel, which is every session recorded without GPS.
    public static func layout(
        mode: SectorMode, session: TelemetrySession, cornerOptions: CornerDetector.Options = .init()
    ) -> SectorLayout? {
        guard let reference = referenceLap(in: session), let distance = session[.distance],
            let length = LapComparison.length(of: reference, distance: distance), length > 0
        else { return nil }

        let boundaries: [Double]
        switch mode {
        case .equalDistance(let count):
            boundaries = equalBoundaries(count: count, length: length)
        case .cornerAware(let count):
            let corners = CornerDetector.corners(of: reference, in: session, options: cornerOptions)
            boundaries = cornerAwareBoundaries(
                count: count, length: length, straights: CornerDetector.straightMidpoints(between: corners))
        case .manual(let lines):
            boundaries = manualBoundaries(lines: lines, lap: reference, session: session, length: length)
        }
        return SectorLayout(
            boundaryDistances: tidied(boundaries, length: length), lapLengthMeters: length,
            referenceLapNumber: reference.number)
    }

    static func equalBoundaries(count: Int, length: Double) -> [Double] {
        let sectors = max(1, count)
        guard sectors > 1 else { return [] }
        return (1..<sectors).map { Double($0) * length / Double(sectors) }
    }

    /// Each equal-distance boundary moves to the nearest straight that no other boundary has
    /// taken, but never by more than half a sector — a circuit whose straights are all in one
    /// place would otherwise give one enormous sector and two tiny ones, which says less about
    /// the driving than an equal split does. A boundary with no straight within reach stays
    /// where the equal split put it, so asking for more sectors than the circuit has straights
    /// still gives that many sectors.
    static func cornerAwareBoundaries(count: Int, length: Double, straights: [Double]) -> [Double] {
        let ideal = equalBoundaries(count: count, length: length)
        guard !straights.isEmpty, count > 1 else { return ideal }
        let maxShift = length / Double(2 * max(1, count))
        var available = straights
        return ideal.map { target in
            guard
                let pick = available.indices.min(by: {
                    abs(available[$0] - target) < abs(available[$1] - target)
                }), abs(available[pick] - target) <= maxShift
            else { return target }
            return available.remove(at: pick)
        }
    }

    /// Each gate becomes the distance at which the reference lap crossed it. A gate the reference
    /// lap never crossed is dropped rather than guessed at.
    static func manualBoundaries(
        lines: [FinishLine], lap: Lap, session: TelemetrySession, length: Double
    ) -> [Double] {
        guard let latitude = session[.latitude], let longitude = session[.longitude],
            let distance = session[.distance], let end = lap.end,
            let startDistance = distance.value(at: lap.start)
        else { return [] }
        return lines.compactMap { line in
            let crossing = LapDetector.crossings(latitude: latitude, longitude: longitude, line: line)
                .first { $0.time > lap.start && $0.time < end }
            guard let crossing, let at = distance.value(at: crossing.time) else { return nil }
            return at - startDistance
        }
    }

    /// Sorts, drops anything on or outside the lap, and drops boundaries a metre apart — two
    /// gates in the same place would otherwise make a sector nobody can drive.
    static func tidied(_ boundaries: [Double], length: Double) -> [Double] {
        var result: [Double] = []
        for value in boundaries.sorted() where value > 1 && value < length - 1 {
            if let last = result.last, value - last < 1 { continue }
            result.append(value)
        }
        return result
    }

    /// Seconds spent in each sector of `lap`. `nil` entries are sectors the lap did not finish.
    public static func times(for lap: Lap, layout: SectorLayout, session: TelemetrySession) -> [Double?] {
        guard let distance = session[.distance], let startDistance = distance.value(at: lap.start) else {
            return [Double?](repeating: nil, count: layout.count)
        }
        let end = lap.end ?? session.timeRange?.upperBound ?? lap.start
        guard end > lap.start else { return [Double?](repeating: nil, count: layout.count) }

        // Time at each boundary, then the lap end. A boundary the lap never reached is nil, and
        // so is every sector after it.
        var edges: [Double?] = [lap.start]
        for boundary in layout.boundaryDistances {
            edges.append(
                LapComparison.time(
                    atDistance: startDistance + boundary, in: distance, between: lap.start, and: end))
        }
        edges.append(lap.isComplete ? end : nil)
        return (0..<layout.count).map { index in
            guard let from = edges[index], let to = edges[index + 1], to >= from else { return nil }
            return to - from
        }
    }

    /// Sector times for every lap of the session under `mode`.
    public static func analyse(
        mode: SectorMode, session: TelemetrySession, cornerOptions: CornerDetector.Options = .init()
    ) -> SectorAnalysis? {
        guard let layout = layout(mode: mode, session: session, cornerOptions: cornerOptions) else { return nil }
        let laps = session.laps.map {
            LapSectors(lapNumber: $0.number, times: times(for: $0, layout: layout, session: session))
        }
        .filter { $0.times.contains { $0 != nil } }
        return SectorAnalysis(layout: layout, laps: laps)
    }
}

extension SectorAnalysis {
    /// Where the car is at `time`: which sector, how long it has been in it, and what this lap's
    /// finished sectors took. `nil` outside every lap.
    public func status(at time: Double, session: TelemetrySession) -> SectorStatus? {
        guard let lap = session.laps.lap(containing: time), let distance = session[.distance],
            let into = LapComparison.distanceIntoLap(at: time, lap: lap, distance: distance)
        else { return nil }
        let index = layout.sector(atDistanceIntoLap: into)
        let times = Sectors.times(for: lap, layout: layout, session: session)
        // Elapsed in this sector = now, less the lap start and every sector already finished.
        let finished = times.prefix(index).compactMap { $0 }.reduce(0, +)
        return SectorStatus(
            lapNumber: lap.number, sectorIndex: index,
            elapsedInSector: max(0, time - lap.start - finished),
            times: times.enumerated().map { $0.offset < index ? $0.element : nil })
    }
}
