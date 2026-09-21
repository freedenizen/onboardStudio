import Foundation

/// Which parts of a recorded trace are the circuit, and which are everything else.
///
/// A session is not only laps. The car leaves the pits, comes back in, is driven to the paddock
/// and parked, and every metre of that is in the file. Drawn on a track map it is worse than
/// clutter: the map is framed to fit the whole trace, so one trip across the paddock shrinks the
/// circuit into a corner of the object.
///
/// Nothing published can be asked where the track is (`docs/tracks-and-sectors.md`), but the
/// driving says it. **A circuit is what gets driven over again and again; a pit lane is not.** So
/// each sample is asked how many separate times the car came within a few metres of it, and the
/// ones with far fewer visits than the busy parts of the trace are not the track.
public enum TrackExtent {
    /// How near two samples must be to count as the same piece of tarmac. Wide enough to cover a
    /// track's width and the scatter between laps, narrow enough that a pit lane running alongside
    /// the pit straight is still a different place.
    public static let defaultRadiusMetres = 12.0

    /// How big a break in the thinned trace means the car left and came back, rather than lingered.
    ///
    /// Counted in thinned samples, which are a fixed distance apart, so this is really a distance:
    /// three of them is about one radius, which is as far as the car can be and still be here.
    ///
    /// **Deliberately not a number of seconds.** A time threshold has to sit below the lap time
    /// and above the time spent crossing a circle, and there is no value that does both for a
    /// Nordschleife lap and a kart lap at once — pick 20 s and a 20 s kart lap counts nine laps as
    /// one visit, which collapses the whole answer. Distance has no such coupling.
    public static let defaultSeparationSamples = 3

    /// Stretches of trace shorter than this are made to agree with what surrounds them.
    ///
    /// A circuit is continuous and so is leaving one. Without this the pit exit merging alongside
    /// the track puts a half-second of "circuit" in the middle of the out lap, and the out lap
    /// rejoining puts a three-second hole just after the start/finish line — measured on the
    /// reference session, and both would draw as visible faults in the outline.
    public static let minimumRunSeconds = 4.0

    /// Below this share of samples surviving, the answer is rejected and everything is kept.
    ///
    /// A point-to-point hillclimb, a single flying lap, a sighting lap and nothing else: traces
    /// with nothing repeated are perfectly ordinary, and drawing almost none of one is a worse
    /// answer than drawing all of it.
    public static let minimumSurvivingShare = 0.35

    /// The session's samples, marked for whether each is on the circuit, worked out once.
    ///
    /// A plan is built per timeline cut and the editor builds its own, so without this the answer
    /// is recomputed several times for every edit made to a project — a third of a second each on
    /// the reference session, which is a preview that feels slow for no reason.
    public static func onTrack(in session: TelemetrySession) -> [Bool] {
        guard let latitude = session[.latitude], let longitude = session[.longitude] else { return [] }
        let key = Fingerprint(session: session, latitude: latitude)
        if let remembered = memo.value(for: key) { return remembered }
        let longitudes =
            longitude.times == latitude.times
            ? longitude.values : latitude.times.map { longitude.value(at: $0) ?? 0 }
        let answer = onTrack(latitudes: latitude.values, longitudes: longitudes, times: latitude.times)
        memo.store(answer, for: key)
        return answer
    }

    /// Enough of a session to tell it from another without comparing every sample: a reimport that
    /// changes the trace changes the count or the ends of it.
    struct Fingerprint: Hashable {
        let count: Int
        let first: Double
        let last: Double
        let firstLatitude: Double
        let lastLatitude: Double

        init(session: TelemetrySession, latitude: Channel) {
            count = latitude.count
            first = latitude.times.first ?? 0
            last = latitude.times.last ?? 0
            firstLatitude = latitude.values.first ?? 0
            lastLatitude = latitude.values.last ?? 0
        }
    }

    /// A handful of answers under a lock, in the manner of `TextDrawing`'s font cache. Small
    /// because one project has one or two data files, not hundreds.
    final class Memo: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [(key: Fingerprint, value: [Bool])] = []
        private let limit = 4

        func value(for key: Fingerprint) -> [Bool]? {
            lock.lock()
            defer { lock.unlock() }
            return entries.first { $0.key == key }?.value
        }

        func store(_ value: [Bool], for key: Fingerprint) {
            lock.lock()
            defer { lock.unlock() }
            entries.removeAll { $0.key == key }
            entries.append((key, value))
            if entries.count > limit { entries.removeFirst(entries.count - limit) }
        }
    }

    static let memo = Memo()

    /// `true` for each sample the car drove over as often as it drove the circuit.
    ///
    /// All `true` when the trace has nothing to say — too few samples, or so little repetition
    /// that the result cannot be trusted.
    public static func onTrack(
        latitudes: [Double],
        longitudes: [Double],
        times: [Double],
        radiusMetres: Double = defaultRadiusMetres,
        separationSamples: Int = defaultSeparationSamples
    ) -> [Bool] {
        let count = min(latitudes.count, min(longitudes.count, times.count))
        guard count > 2, radiusMetres > 0 else { return Array(repeating: true, count: count) }
        // Answered on a thinned copy of the trace and read back onto every sample. Whether a place
        // is the circuit is a property of the place, so a logger recording at 93 Hz asks the same
        // question ten times per car length and pays for all ten: on the reference session that is
        // the difference between two minutes of work and a moment of it.
        let marks = thinned(
            latitudes: latitudes, longitudes: longitudes, count: count, spacing: radiusMetres / 3)
        let visits = visitCounts(
            latitudes: marks.map { latitudes[$0] }, longitudes: marks.map { longitudes[$0] },
            count: marks.count, radiusMetres: radiusMetres, separationSamples: separationSamples)
        // The busy parts of a trace are the circuit, because that is where the time goes; half as
        // many visits as typical is the line between a lap and an errand.
        //
        // Never below three, and that floor is what does the work on a short session. **A pit lane
        // is driven twice however many laps follow it** — out at the start, in at the end — so a
        // proportional threshold alone lets it through on anything under six laps. Three laps is
        // the fewest that can tell a circuit from an errand at all, and below that the surviving
        // share rejects the answer and the whole trace is drawn.
        let typical = median(of: visits)
        let threshold = max(3, (typical + 1) / 2)
        let spreadOut = spread(visits.map { $0 >= threshold }, from: marks, over: count)
        let keep = settled(spreadOut, times: times, shorterThan: minimumRunSeconds)
        let surviving = keep.reduce(0) { $0 + ($1 ? 1 : 0) }
        guard Double(surviving) >= Double(count) * minimumSurvivingShare else {
            return Array(repeating: true, count: count)
        }
        return keep
    }

    /// Sample indices spaced at least `spacing` metres apart along the trace.
    ///
    /// By distance rather than by every *n*th sample: a stride tuned to one file leaves gaps wider
    /// than the search radius in a longer one, and a gap there does not slow the answer down, it
    /// makes it wrong — a lap whose samples fall between the circles is a lap that never happened.
    static func thinned(latitudes: [Double], longitudes: [Double], count: Int, spacing: Double) -> [Int] {
        let cosLat = cos(latitudes[count / 2] * .pi / 180)
        var kept = [0]
        var lastLatitude = latitudes[0]
        var lastLongitude = longitudes[0]
        let spacingSquared = spacing * spacing
        for index in 1..<count {
            let de = (longitudes[index] - lastLongitude) * cosLat * 111_320
            let dn = (latitudes[index] - lastLatitude) * 110_540
            guard de * de + dn * dn >= spacingSquared else { continue }
            kept.append(index)
            lastLatitude = latitudes[index]
            lastLongitude = longitudes[index]
        }
        return kept
    }

    /// Gives any stretch shorter than `seconds` the answer of the stretch it follows.
    ///
    /// **Absorbed into what came before, not flipped.** Flipping each short run on its own reads
    /// correctly for one blip between two long stretches, and inverts the middle of three or more
    /// short runs in a row — which is the noisy case this exists for, where a pit road runs within
    /// the search radius of the track. There it leaves a hole in the outline instead of closing
    /// one, and a hole in the outline is a circuit drawn broken.
    ///
    /// A short run at the very front has nothing before it, so it takes what the trace settles
    /// into instead. A trace with no long run anywhere is left exactly as it is.
    static func settled(_ keep: [Bool], times: [Double], shorterThan seconds: Double) -> [Bool] {
        guard keep.count > 1, keep.count <= times.count else { return keep }
        var result = keep
        // The last stretch long enough to stand on its own, held as where it starts rather than
        // as what it said, so "nothing yet" needs no second value for a boolean.
        var inForce: Int?
        var pendingStart: Int?
        for run in runs(of: keep) {
            let last = min(run.upperBound, keep.count - 1)
            guard times[last] - times[run.lowerBound] >= seconds else {
                if let current = inForce {
                    for position in run { result[position] = keep[current] }
                } else if pendingStart == nil {
                    pendingStart = run.lowerBound
                }
                continue
            }
            if let start = pendingStart {
                for position in start..<run.lowerBound { result[position] = keep[run.lowerBound] }
                pendingStart = nil
            }
            inForce = run.lowerBound
        }
        return result
    }

    /// The stretches of equal values in `keep`, as ranges into it.
    static func runs(of keep: [Bool]) -> [Range<Int>] {
        guard !keep.isEmpty else { return [] }
        var result: [Range<Int>] = []
        var start = 0
        for index in 1...keep.count where index == keep.count || keep[index] != keep[start] {
            result.append(start..<index)
            start = index
        }
        return result
    }

    /// Reads the thinned answer back onto every sample, each taking the nearest one asked.
    static func spread(_ answers: [Bool], from marks: [Int], over count: Int) -> [Bool] {
        guard !answers.isEmpty, answers.count == marks.count else {
            return Array(repeating: true, count: count)
        }
        var result = [Bool](repeating: answers[0], count: count)
        var mark = 0
        for index in 0..<count {
            // Walk forward to the last mark at or before this sample, then take whichever of it
            // and the next one is nearer.
            while mark + 1 < marks.count, marks[mark + 1] <= index { mark += 1 }
            let next = min(mark + 1, marks.count - 1)
            let nearer = (index - marks[mark]) <= (marks[next] - index) ? mark : next
            result[index] = answers[nearer]
        }
        return result
    }

    /// How many separate times the car came within `radiusMetres` of each sample.
    ///
    /// Visits are found by time, not by counting neighbouring samples: a car crawling through the
    /// paddock leaves dozens of samples in one spot, and they are one visit, not dozens.
    static func visitCounts(
        latitudes: [Double],
        longitudes: [Double],
        count: Int,
        radiusMetres: Double,
        separationSamples: Int
    ) -> [Int] {
        let cosLat = cos((latitudes[count / 2]) * .pi / 180)
        // Metres east and north of the first sample; a track day fits inside a few kilometres, so
        // a flat local frame is exact enough and much cheaper than a spherical one.
        var east = [Double](repeating: 0, count: count)
        var north = [Double](repeating: 0, count: count)
        for index in 0..<count {
            east[index] = (longitudes[index] - longitudes[0]) * cosLat * 111_320
            north[index] = (latitudes[index] - latitudes[0]) * 110_540
        }
        var grid: [Cell: [Int]] = [:]
        for index in 0..<count {
            grid[Cell(east: east[index], north: north[index], size: radiusMetres), default: []].append(index)
        }
        let radiusSquared = radiusMetres * radiusMetres
        var visits = [Int](repeating: 0, count: count)
        var neighbours: [Int] = []
        for index in 0..<count {
            neighbours.removeAll(keepingCapacity: true)
            let home = Cell(east: east[index], north: north[index], size: radiusMetres)
            for dx in -1...1 {
                for dy in -1...1 {
                    for other in grid[Cell(x: home.x + dx, y: home.y + dy)] ?? [] {
                        let de = east[other] - east[index]
                        let dn = north[other] - north[index]
                        if de * de + dn * dn <= radiusSquared { neighbours.append(other) }
                    }
                }
            }
            visits[index] = visitCount(of: neighbours.sorted(), separatedBy: separationSamples)
        }
        return visits
    }

    /// Runs of sample indices more than `separation` apart, which is the number of separate visits.
    ///
    /// One pass through a place is a run of consecutive samples, however many of them there are
    /// and however long the car took over them; coming back later leaves a gap in the middle.
    static func visitCount(of sortedIndices: [Int], separatedBy separation: Int) -> Int {
        guard var previous = sortedIndices.first else { return 0 }
        var visits = 1
        for index in sortedIndices.dropFirst() {
            if index - previous > separation { visits += 1 }
            previous = index
        }
        return visits
    }

    static func median(of values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        return values.sorted()[values.count / 2]
    }

    /// A square of the local grid, so each sample only measures against those nearby.
    struct Cell: Hashable {
        let x: Int
        let y: Int

        init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }

        init(east: Double, north: Double, size: Double) {
            x = Int((east / size).rounded(.down))
            y = Int((north / size).rounded(.down))
        }
    }
}
