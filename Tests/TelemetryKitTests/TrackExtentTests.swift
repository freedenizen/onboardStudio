import Foundation
import Testing

@testable import TelemetryKit

/// A square circuit reached down a straight access road, which is what a pit lane and a paddock
/// look like to this: driven once on the way out, once on the way back, and never again.
///
/// The square is deliberately the same one `SectorMapSession` uses in the render tests, so a fact
/// established here is a fact about the same shape that gets drawn there.
enum PitLaneSession {
    static let side = 100.0
    static let roadLength = 200.0
    static let origin = (latitude: 45.0, longitude: -122.0)
    static let step = 2.0
    static let speed = 20.0
    static var metresPerDegreeEast: Double { 111_320 * cos(origin.latitude * .pi / 180) }

    /// Metres east and north of the square's south-west corner after `travelled` metres of a lap.
    static func lapPoint(at travelled: Double) -> (east: Double, north: Double) {
        let s = travelled.truncatingRemainder(dividingBy: 4 * side)
        switch s {
        case ..<side: return (0, s)
        case ..<(2 * side): return (s - side, side)
        case ..<(3 * side): return (side, 3 * side - s)
        default: return (4 * side - s, 0)
        }
    }

    /// An outing and the arrays it was built from, so a test can measure against the shape it
    /// asked for rather than digging the channels back out of the session.
    struct Outing {
        let session: TelemetrySession
        let east: [Double]
        let latitudes: [Double]
        let longitudes: [Double]
        let times: [Double]

        /// True for the samples on the square rather than on the access road.
        var onSquare: [Bool] { east.map { $0 > -step } }
    }

    static func outing(laps: Int) -> Outing {
        let session = session(laps: laps)
        let (east, _) = path(laps: laps)
        let times = (0..<east.count).map { Double($0) * step / speed }
        return Outing(
            session: session, east: east,
            latitudes: session[.latitude].map(\.values) ?? [],
            longitudes: session[.longitude].map(\.values) ?? [], times: times)
    }

    /// Metres east and north of the square's south-west corner, sample by sample.
    static func path(laps: Int) -> (east: [Double], north: [Double]) {
        var east: [Double] = []
        var north: [Double] = []
        for metre in stride(from: -roadLength, to: 0.0, by: step) {
            east.append(metre)
            north.append(0)
        }
        for _ in 0..<laps {
            for metre in stride(from: 0.0, to: 4 * side, by: step) {
                let point = lapPoint(at: metre)
                east.append(point.east)
                north.append(point.north)
            }
        }
        for metre in stride(from: 0.0, through: -roadLength, by: -step) {
            east.append(metre)
            north.append(0)
        }
        return (east, north)
    }

    /// The whole outing: in down the road, `laps` of the square, out up the road again.
    ///
    /// The road runs due west of the square so it cannot be mistaken for part of it — a road
    /// alongside the straight is a harder case, and one this deliberately does not claim to solve.
    static func session(laps: Int) -> TelemetrySession {
        let (east, north) = path(laps: laps)
        let times = (0..<east.count).map { Double($0) * step / speed }
        let latitudes = north.map { origin.latitude + $0 / 110_540 }
        let longitudes = east.map { origin.longitude + $0 / metresPerDegreeEast }
        return TelemetrySession(
            info: SessionInfo(sourceFormat: "synthetic"),
            channels: [
                Channel(role: .latitude, name: "lat", unit: .degrees, times: times, values: latitudes),
                Channel(role: .longitude, name: "lon", unit: .degrees, times: times, values: longitudes),
            ],
            laps: [])
    }

}

@Suite("Track extent")
struct TrackExtentTests {
    /// How far down the road the answer still calls it circuit, and whether the square came
    /// through whole. `nil` reach means none of the road survived at all.
    func answer(laps: Int) -> (squareDropped: Int, roadReach: Double?) {
        let outing = PitLaneSession.outing(laps: laps)
        let keep = TrackExtent.onTrack(in: outing.session)
        let east = outing.east
        let squareDropped = zip(keep, east).filter { $0.1 > -PitLaneSession.step }.filter { !$0.0 }.count
        let roadKept = zip(keep, east).filter { $0.1 <= -PitLaneSession.step }.filter { $0.0 }.map(\.1)
        return (squareDropped, roadKept.min().map { -$0 })
    }

    @Test("The access road is left out and the circuit is kept whole")
    func dropsWhatWasDrivenOnce() {
        let (squareDropped, roadReach) = answer(laps: 6)
        #expect(squareDropped == 0)
        // Some of the road survives, and it should: the last few metres of it are within a car's
        // length of the track, and a place that close to the circuit is not distinguishable from
        // it by this or by any other means. What matters is that it stops there — stated as a
        // distance from the junction rather than as a share of the road, because the share
        // depends on how long the road is and the distance does not.
        #expect((roadReach ?? 0) < TrackExtent.defaultRadiusMetres + PitLaneSession.step)
    }

    @Test("A pit lane is driven twice however many laps follow, so two visits is never enough")
    func threeLapsIsEnoughToTell() {
        // The proportional half-of-typical threshold alone would pass a road driven twice on any
        // session under six laps. Three is where telling them apart becomes possible at all.
        for laps in [3, 4, 6, 10] {
            let (squareDropped, roadReach) = answer(laps: laps)
            #expect(squareDropped == 0, "laps: \(laps)")
            #expect((roadReach ?? 0) < TrackExtent.defaultRadiusMetres + PitLaneSession.step, "laps: \(laps)")
        }
    }

    @Test("Too little repetition to tell, so the whole trace is drawn")
    func keepsEverythingWhenNothingRepeats() {
        // Two laps: the square was driven twice and so was the road. There is nothing here that
        // distinguishes them, and drawing almost none of the trace would be a worse answer than
        // drawing all of it.
        #expect(TrackExtent.onTrack(in: PitLaneSession.session(laps: 2)).allSatisfy { $0 })
        // A single run down the road and back, with no circuit at all.
        let out = PitLaneSession.session(laps: 0)
        #expect(TrackExtent.onTrack(in: out).allSatisfy { $0 })
    }

    @Test("A session with no position says nothing")
    func handlesASessionWithoutPosition() {
        let bare = TelemetrySession(
            info: SessionInfo(sourceFormat: "synthetic"),
            channels: [Channel(role: .speed, name: "v", unit: .metersPerSecond, times: [0, 1], values: [10, 11])],
            laps: [])
        #expect(TrackExtent.onTrack(in: bare).isEmpty)
    }

    // MARK: - The pieces

    @Test("A visit is one unbroken pass, however many samples it took")
    func countsPassesNotSamples() {
        // Fifty samples in a row through one place is one visit, not fifty.
        #expect(TrackExtent.visitCount(of: Array(0..<50), separatedBy: 3) == 1)
        // Three passes, each leaving a gap where the car was elsewhere.
        #expect(TrackExtent.visitCount(of: [0, 1, 100, 101, 200], separatedBy: 3) == 3)
        #expect(TrackExtent.visitCount(of: [], separatedBy: 3) == 0)
        // Exactly the separation is not yet a new visit; it has to be further.
        #expect(TrackExtent.visitCount(of: [0, 3], separatedBy: 3) == 1)
        #expect(TrackExtent.visitCount(of: [0, 4], separatedBy: 3) == 2)
    }

    @Test("A short lap counts as many visits as it was driven")
    func doesNotDependOnTheLapTime() {
        // The reason visits are counted by distance and not by seconds. This square takes 20 s a
        // lap; a fixed 20 s separation would fold all six laps into one visit, the answer would
        // collapse and the whole trace would be drawn — including the road.
        let outing = PitLaneSession.outing(laps: 6)
        let latitudes = outing.latitudes
        let longitudes = outing.longitudes
        let marks = TrackExtent.thinned(
            latitudes: latitudes, longitudes: longitudes, count: latitudes.count,
            spacing: TrackExtent.defaultRadiusMetres / 3)
        let visits = TrackExtent.visitCounts(
            latitudes: marks.map { latitudes[$0] }, longitudes: marks.map { longitudes[$0] },
            count: marks.count, radiusMetres: TrackExtent.defaultRadiusMetres,
            separationSamples: TrackExtent.defaultSeparationSamples)
        #expect(TrackExtent.median(of: visits) == 6)
    }

    @Test("Thinning keeps the trace's shape at a spacing, whatever the sample rate")
    func thinsByDistance() {
        let outing = PitLaneSession.outing(laps: 3)
        let latitudes = outing.latitudes
        let longitudes = outing.longitudes
        let marks = TrackExtent.thinned(
            latitudes: latitudes, longitudes: longitudes, count: latitudes.count, spacing: 8)
        #expect(marks.count < latitudes.count / 3)
        #expect(marks.first == 0)
        // Every kept sample is at least the spacing from the one before, and never much more:
        // the gaps follow the ground covered, not the number of rows in the file. The ceiling is
        // the spacing plus one sample step, since a mark is kept as soon as it clears.
        var worstGap = 0.0
        var closest = Double.infinity
        for (a, b) in zip(marks, marks.dropFirst()) {
            let de = (longitudes[b] - longitudes[a]) * PitLaneSession.metresPerDegreeEast
            let dn = (latitudes[b] - latitudes[a]) * 110_540
            let gap = (de * de + dn * dn).squareRoot()
            worstGap = max(worstGap, gap)
            closest = min(closest, gap)
        }
        #expect(closest >= 8 - 0.001)
        #expect(worstGap <= 8 + PitLaneSession.step + 0.001)
    }

    @Test("How finely the trace is thinned does not change the answer")
    func thinningIsNotLoadBearing() {
        // The thinning is there for speed and must not be doing any of the deciding. Asked at
        // three resolutions — one much finer than the default, one coarser — the answer is the
        // same answer.
        let outing = PitLaneSession.outing(laps: 6)
        let square = outing.onSquare
        for radius in [TrackExtent.defaultRadiusMetres, 6.0, 20.0] {
            let keep = TrackExtent.onTrack(
                latitudes: outing.latitudes, longitudes: outing.longitudes, times: outing.times,
                radiusMetres: radius)
            let roadKept = zip(keep, square).filter { !$0.1 }.filter { $0.0 }.count
            let roadTotal = square.filter { !$0 }.count
            let squareDropped = zip(keep, square).filter { $0.1 }.filter { !$0.0 }.count
            #expect(Double(roadKept) < Double(roadTotal) * 0.15, "radius: \(radius)")
            #expect(squareDropped == 0, "radius: \(radius)")
        }
    }

    @Test("Brief stretches are made to agree with what surrounds them")
    func settlesShortRuns() {
        let times = (0..<100).map { Double($0) }
        // One second of "off" in the middle of a minute of "on" is noise, not an excursion.
        var keep = [Bool](repeating: true, count: 100)
        keep[50] = false
        #expect(TrackExtent.settled(keep, times: times, shorterThan: 4).allSatisfy { $0 })
        // A stretch longer than the minimum stays as it is.
        var real = [Bool](repeating: true, count: 100)
        for index in 40..<60 { real[index] = false }
        let settled = TrackExtent.settled(real, times: times, shorterThan: 4)
        #expect(settled[50] == false)
        #expect(settled[30] == true)
        // A trace that says one thing throughout is left alone however short it is.
        let uniform = [Bool](repeating: true, count: 3)
        #expect(TrackExtent.settled(uniform, times: [0, 1, 2], shorterThan: 4) == uniform)
    }

    @Test("The answer is worked out once per session")
    func remembersItsAnswer() {
        let session = PitLaneSession.session(laps: 6)
        let first = TrackExtent.onTrack(in: session)
        let started = Date()
        let second = TrackExtent.onTrack(in: session)
        // Same answer, and returned without doing the work again — a plan is built per timeline
        // cut and the editor builds its own, so this is asked several times per edit.
        #expect(first == second)
        #expect(Date().timeIntervalSince(started) < 0.01)
    }
}
