import CoreGraphics
import CoreVideo
import Foundation
import ProjectModel
import TelemetryKit
import Testing

@testable import RenderKit

/// Three laps of a square 100 m on a side, driven anticlockwise from the south-west corner at a
/// steady 20 m/s, with the distance channel and three equal sectors measured.
///
/// Laps and geometry agree here, which the shared `SyntheticSession` does not manage — its lap
/// list and its position function have different periods, so a sector colour on it would fall
/// wherever the arithmetic landed. A 400 m lap in three makes S1 the west side plus a third of
/// the north, and that is legible in a golden.
enum SectorMapSession {
    static let side = 100.0
    static let lapLength = 4 * side
    static let laps = 3
    static let speed = 20.0
    static let origin = (latitude: 45.0, longitude: -122.0)

    /// Metres east and north of `origin` after `travelled` metres of a lap.
    static func point(at travelled: Double) -> (east: Double, north: Double) {
        let s = travelled.truncatingRemainder(dividingBy: lapLength)
        switch s {
        case ..<side: return (0, s)  // west side, heading north
        case ..<(2 * side): return (s - side, side)  // north side, heading east
        case ..<(3 * side): return (side, 3 * side - s)  // east side, heading south
        default: return (4 * side - s, 0)  // south side, heading west
        }
    }

    static let session: TelemetrySession = {
        let step = 2.0
        let metresPerDegreeEast = 111_320 * cos(origin.latitude * .pi / 180)
        var times: [Double] = []
        var latitudes: [Double] = []
        var longitudes: [Double] = []
        var distances: [Double] = []
        var lapList: [Lap] = []
        var travelled = 0.0
        for lap in 0..<laps {
            let start = travelled / speed
            var into = 0.0
            while into < lapLength {
                let position = point(at: into)
                times.append((Double(lap) * lapLength + into) / speed)
                latitudes.append(origin.latitude + position.north / 110_540)
                longitudes.append(origin.longitude + position.east / metresPerDegreeEast)
                distances.append(Double(lap) * lapLength + into)
                into += step
            }
            travelled += lapLength
            lapList.append(Lap(number: lap + 1, start: start, end: travelled / speed, isComplete: true))
        }
        times.append(travelled / speed)
        latitudes.append(origin.latitude)
        longitudes.append(origin.longitude)
        distances.append(travelled)
        var session = TelemetrySession(
            info: SessionInfo(sourceFormat: "synthetic"),
            channels: [
                Channel(role: .latitude, name: "lat", unit: .degrees, times: times, values: latitudes),
                Channel(role: .longitude, name: "lon", unit: .degrees, times: times, values: longitudes),
                Channel(role: .distance, name: "d", unit: .meters, times: times, values: distances),
            ],
            laps: lapList)
        session.sectors = Sectors.analyse(mode: .equalDistance(count: 3), session: session)
        return session
    }()
}

@Suite("Track map display options")
struct TrackMapDisplayTests {
    let size = CGSize(width: 300, height: 300)

    func renderer(_ params: TrackMapParams, session: TelemetrySession = SectorMapSession.session)
        -> TrackMapRenderer
    {
        TrackMapRenderer(
            context: ObjectContext(
                objectID: DisplayObjectID(UUID(uuidString: "00000000-0000-0000-0000-000000000004") ?? UUID()),
                frame: UnitRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9), opacity: 1,
                sampler: TelemetrySampler(session: session), sync: .identity, cache: RenderCache()),
            params: params)
    }

    @Test func theSessionUnderTestHasSectors() throws {
        #expect(try #require(SectorMapSession.session.sectors).count == 3)
    }

    // MARK: - Nothing changes unless it is asked for

    @Test func aPlainMapComputesNoMarks() {
        let marks = renderer(TrackMapParams()).marks
        #expect(marks.sectorOfPoint.isEmpty)
        #expect(marks.boundaries.isEmpty)
        #expect(marks.corners.isEmpty)
    }

    @Test func aPlainMapStrokesTheWholeTraceInOneRun() throws {
        let runs = renderer(TrackMapParams()).outlineRuns(segments: [0..<100], count: 100)
        #expect(runs.count == 1)
        #expect(runs[0].range == 0..<100)
        // −1 means "no sector", which draws in the plain line colour.
        #expect(runs[0].sector == -1)
    }

    // MARK: - Sector colouring

    @Test func colouringSplitsTheOutlineIntoRunsThatMeet() throws {
        var params = TrackMapParams()
        params.colorBySector = true
        let panel = renderer(params)
        let count = panel.marks.sectorOfPoint.count
        let runs = panel.outlineRuns(segments: [0..<count], count: count)
        #expect(runs.count > 1)
        // Consecutive runs share a point, or the colours would leave a gap between them.
        for (a, b) in zip(runs, runs.dropFirst()) {
            #expect(b.range.lowerBound == a.range.upperBound - 1)
        }
        #expect(runs.first?.range.lowerBound == 0)
        #expect(runs.last?.range.upperBound == count)
    }

    @Test func everySectorGetsItsOwnColourAndTheyCycle() {
        var params = TrackMapParams()
        params.colorBySector = true
        let panel = renderer(params)
        #expect(panel.colour(ofSector: 0) == TrackMapParams.defaultSectorColors[0])
        #expect(panel.colour(ofSector: 2) == TrackMapParams.defaultSectorColors[2])
        // More sectors than colours cycles rather than running out.
        #expect(panel.colour(ofSector: 3) == TrackMapParams.defaultSectorColors[0])
        // A point in no sector, and an empty palette, both fall back to the plain line colour.
        #expect(panel.colour(ofSector: -1) == params.lineColor)
        var bare = params
        bare.sectorColors = []
        #expect(renderer(bare).colour(ofSector: 1) == bare.lineColor)
    }

    // MARK: - Ticks

    @Test func aTickSitsWhereTheSectorLayoutSaysTheBoundaryIs() throws {
        var params = TrackMapParams()
        params.showSectorTicks = true
        let panel = renderer(params)
        let layout = try #require(SectorMapSession.session.sectors).layout
        #expect(panel.marks.boundaries.count == layout.boundaryDistances.count)
        // Turn each tick's position back into a distance into the lap; it must be the boundary
        // it was made from. This is the check that a tick is drawn where it is timed.
        let reference = try #require(Sectors.referenceLap(in: SectorMapSession.session))
        let distance = try #require(SectorMapSession.session[.distance])
        let lapStart = try #require(distance.value(at: reference.start))
        for (boundary, expected) in zip(panel.marks.boundaries, layout.boundaryDistances) {
            let into = try #require(distance.value(at: boundary.time)) - lapStart
            #expect(abs(into - expected) < 1)
        }
    }

    @Test func aTickIsSquareToTheDirectionOfTravel() throws {
        // Found in review: the step used to find the direction of travel is in degrees, and the
        // projection scales longitude by cosLat — so without dividing the longitude step by
        // cosLat the tick came out as atan(tan(heading) · cosLat), 13° off a diagonal heading at
        // Silverstone's latitude. Measure the projected direction and compare it with the real one.
        var params = TrackMapParams()
        params.showSectorTicks = true
        let panel = renderer(params)
        let projection = try #require(panel.projection)
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 300)
        let origin = SectorMapSession.origin
        for heading in stride(from: 0.0, to: 360.0, by: 15) {
            let boundary = LapComparison.LapPoint(
                time: 0, latitude: origin.latitude, longitude: origin.longitude, headingDegrees: heading)
            let travel = try #require(panel.direction(of: boundary, projection: projection, bounds: bounds))
            // Map space is y-down, so a bearing of 0 (north) points at −y.
            let projected = (atan2(travel.x, -travel.y) * 180 / .pi + 360)
                .truncatingRemainder(dividingBy: 360)
            var off = abs(projected - heading).truncatingRemainder(dividingBy: 360)
            if off > 180 { off = 360 - off }
            #expect(off < 0.5, "heading \(heading)° projected as \(projected)°")
        }
    }

    @Test func thereIsNoTickForTheFirstSector() throws {
        var params = TrackMapParams()
        params.showSectorTicks = true
        // Three sectors, two boundaries: the first begins at the start/finish line, which is not
        // a sector boundary.
        #expect(renderer(params).marks.boundaries.count == 2)
    }

    // MARK: - Corners

    @Test func withoutNamesTheMapCountsTheCorners() throws {
        var params = TrackMapParams()
        params.showCornerNumbers = true
        let marks = renderer(params).marks
        #expect(marks.labels.isEmpty)
        // A count, deliberately: the circuit's own numbering is not derivable and Sonoma runs
        // 3, 3a, 4, 4a, so 1…N would be wrong if it claimed to be the real thing.
        #expect(marks.cornerLabel(0) == "1")
        #expect(marks.cornerLabel(3) == "4")
    }

    @Test func theCircuitsOwnNamesAreUsedWhenThereAreSome() throws {
        var session = SectorMapSession.session
        session.cornerLabels = ["1", "2", "3", "3a"]
        var params = TrackMapParams()
        params.showCornerNumbers = true
        let marks = renderer(params, session: session).marks
        #expect(marks.cornerLabel(2) == "3")
        // The case this whole thing exists for.
        #expect(marks.cornerLabel(3) == "3a")
    }

    @Test func aMissingOrBlankNameFallsBackToTheCount() throws {
        var session = SectorMapSession.session
        // Shorter than the corner list, and with a gap in it.
        session.cornerLabels = ["1", "", "3"]
        var params = TrackMapParams()
        params.showCornerNumbers = true
        let marks = renderer(params, session: session).marks
        #expect(marks.cornerLabel(0) == "1")
        #expect(marks.cornerLabel(1) == "2")  // blank
        #expect(marks.cornerLabel(2) == "3")
        #expect(marks.cornerLabel(9) == "10")  // past the end of the list
    }

    @Test func cornerMarksMatchTheDetector() throws {
        var params = TrackMapParams()
        params.showCornerNumbers = true
        let reference = try #require(Sectors.referenceLap(in: SectorMapSession.session))
        let corners = CornerDetector.corners(of: reference, in: SectorMapSession.session)
        #expect(renderer(params).marks.corners.count == corners.count)
    }

    // MARK: - Which part of the session is drawn

    @Test func theReferenceLapDrawsFewerPointsAndFramesItself() throws {
        let whole = try #require(renderer(TrackMapParams()).projection)
        var params = TrackMapParams()
        params.trace = .referenceLap
        let lap = try #require(renderer(params).projection)
        #expect(lap.points.count < whole.points.count)
        #expect(lap.points.count > 2)
        let reference = try #require(Sectors.referenceLap(in: SectorMapSession.session))
        #expect(lap.times.allSatisfy { $0 >= reference.start && $0 <= (reference.end ?? .infinity) })
    }

    @Test func aProjectionsTimesLineUpWithItsPoints() throws {
        let projection = try #require(renderer(TrackMapParams()).projection)
        #expect(projection.times.count == projection.points.count)
    }

    @Test func aSessionWithoutSectorsStillDrawsItsOutline() throws {
        var params = TrackMapParams()
        params.colorBySector = true
        params.showSectorTicks = true
        params.showCornerNumbers = true
        // SyntheticSession has no distance channel and no measured sectors.
        let panel = renderer(params, session: SyntheticSession.session)
        #expect(panel.marks.boundaries.isEmpty)
        #expect(panel.projection != nil)
        #expect(panel.outlineRuns(segments: [0..<50], count: 50).count == 1)
    }

    // MARK: - The track only

    /// The square, reached down a 200 m access road driven once each way — the shape of a pit lane
    /// and a paddock. Six laps, so the circuit is plainly the repeated part.
    /// How many samples `withPitLane` holds, kept beside it so a test need not unwrap a channel.
    static let pitLaneSampleCount = 100 + 6 * Int(SectorMapSession.lapLength / 2) + 101

    static let withPitLane: TelemetrySession = {
        let metresPerDegreeEast = 111_320 * cos(SectorMapSession.origin.latitude * .pi / 180)
        var east: [Double] = []
        var north: [Double] = []
        for metre in stride(from: -200.0, to: 0.0, by: 2) {
            east.append(metre)
            north.append(0)
        }
        for _ in 0..<6 {
            for metre in stride(from: 0.0, to: SectorMapSession.lapLength, by: 2) {
                let point = SectorMapSession.point(at: metre)
                east.append(point.east)
                north.append(point.north)
            }
        }
        for metre in stride(from: 0.0, through: -200.0, by: -2) {
            east.append(metre)
            north.append(0)
        }
        let times = (0..<east.count).map { Double($0) * 2 / SectorMapSession.speed }
        return TelemetrySession(
            info: SessionInfo(sourceFormat: "synthetic"),
            channels: [
                Channel(
                    role: .latitude, name: "lat", unit: .degrees, times: times,
                    values: north.map { SectorMapSession.origin.latitude + $0 / 110_540 }),
                Channel(
                    role: .longitude, name: "lon", unit: .degrees, times: times,
                    values: east.map { SectorMapSession.origin.longitude + $0 / metresPerDegreeEast }),
            ],
            laps: [])
    }()

    @Test func theTrackOnlyMapFramesTheCircuitAndNotTheAccessRoad() throws {
        let whole = try #require(
            TrackProjection(session: Self.withPitLane, params: TrackMapParams(trace: .wholeSession)))
        let track = try #require(
            TrackProjection(session: Self.withPitLane, params: TrackMapParams(trace: .trackOnly)))
        // This is the whole point of #95. The road is 200 m long and the square 100 m on a side,
        // so drawing everything makes the map three times wider than the circuit and squashes the
        // circuit into the right-hand third of the object.
        let wholeWidth = whole.maxX - whole.minX
        let trackWidth = track.maxX - track.minX
        #expect(wholeWidth > trackWidth * 2.5)
        // The square is 100 m across, and a degree of longitude here is shortened by cosLat, so
        // the projected span works out in degrees of latitude.
        #expect(abs(trackWidth * 111_320 - 100) < 30)
        // The height is the square's side either way: the road is due west and stretches nothing.
        #expect(abs((whole.maxY - whole.minY) - (track.maxY - track.minY)) < 1e-9)
    }

    @Test func theOutlineLiftsThePenRatherThanRulingALineAcross() throws {
        let track = try #require(
            TrackProjection(session: Self.withPitLane, params: TrackMapParams(trace: .trackOnly)))
        // Out and back are two separate absences, so what is left is one unbroken stretch. Were
        // the two ends simply joined, the map would show a line straight across the circuit from
        // where the car left it to where it came back.
        #expect(track.segments.count == 1)
        #expect(try track.points.count < whole(Self.withPitLane).points.count)

        // A trace with a hole in the middle keeps both sides and draws neither into the other.
        let projection = try #require(
            TrackProjection(
                session: Self.withPitLane, rotationDegrees: 0,
                onTrack: (0..<Self.pitLaneSampleCount).map { $0 < 100 || $0 > 300 }))
        #expect(projection.segments.count == 2)
        #expect(projection.segments[0].upperBound == projection.segments[1].lowerBound)
        let panel = renderer(TrackMapParams(), session: Self.withPitLane)
        let runs = panel.outlineRuns(segments: projection.segments, count: projection.points.count)
        #expect(runs.count == 2)
        // No run spans the join, which is what stroking a single path over the gap would do.
        #expect(runs.allSatisfy { run in projection.segments.contains { $0 == run.range } })
    }

    @Test func aSessionWithNothingRepeatedIsDrawnWhole() throws {
        // `SectorMapSession` never leaves the square, so asking for the track only asks for all of
        // it — a map that suddenly drew less of an ordinary session would be a bug, not a feature.
        let all = try #require(
            TrackProjection(session: SectorMapSession.session, params: TrackMapParams(trace: .wholeSession)))
        let track = try #require(
            TrackProjection(session: SectorMapSession.session, params: TrackMapParams(trace: .trackOnly)))
        #expect(track.points.count == all.points.count)
        #expect(track.segments == all.segments)
    }

    @Test func theCarIsHeldInsideTheMapWhenItIsSomewhereTheMapDoesNotShow() {
        let panel = renderer(TrackMapParams(), session: Self.withPitLane)
        let rect = CGRect(x: 20, y: 30, width: 100, height: 80)
        // A point well outside, as the car in the pit lane projects once the pit lane is not drawn.
        // The dot is not part of the cached trace image, so unheld it draws loose over the video.
        let held = panel.held(CGPoint(x: -400, y: 500), inside: rect, radius: 5)
        #expect(held.x == rect.minX + 5)
        #expect(held.y == rect.maxY - 5)
        // A point inside is left exactly where it is.
        let inside = panel.held(CGPoint(x: 40, y: 20), inside: rect, radius: 5)
        #expect(inside == CGPoint(x: rect.minX + 40, y: rect.minY + 20))
    }

    func whole(_ session: TelemetrySession) throws -> TrackProjection {
        try #require(TrackProjection(session: session, params: TrackMapParams(trace: .wholeSession)))
    }

    // MARK: - Goldens

    @Test func sectorColouringWithTicks() throws {
        var params = TrackMapParams(backgroundColor: .faceDark)
        params.colorBySector = true
        params.showSectorTicks = true
        try GoldenImage.assertMatches(try render(params), named: "trackmap-sectors")
    }

    @Test func cornerNumbersOnTheReferenceLap() throws {
        var params = TrackMapParams(backgroundColor: .faceDark)
        params.trace = .referenceLap
        params.showCornerNumbers = true
        try GoldenImage.assertMatches(try render(params), named: "trackmap-corners-reference-lap")
    }

    func render(_ params: TrackMapParams, time: Double = 5) throws -> CVPixelBuffer {
        let plan = RenderPlan(
            outputWidth: Int(size.width), outputHeight: Int(size.height), frameRate: 30, videoLayers: [],
            overlays: [renderer(params)])
        return try FrameCompositor(plan: plan).renderFrame(sources: [:], time: time)
    }
}
