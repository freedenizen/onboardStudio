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
        let runs = renderer(TrackMapParams()).outlineRuns(count: 100)
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
        let runs = panel.outlineRuns(count: panel.marks.sectorOfPoint.count)
        #expect(runs.count > 1)
        // Consecutive runs share a point, or the colours would leave a gap between them.
        for (a, b) in zip(runs, runs.dropFirst()) {
            #expect(b.range.lowerBound == a.range.upperBound - 1)
        }
        #expect(runs.first?.range.lowerBound == 0)
        #expect(runs.last?.range.upperBound == panel.marks.sectorOfPoint.count)
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

    @Test func thereIsNoTickForTheFirstSector() throws {
        var params = TrackMapParams()
        params.showSectorTicks = true
        // Three sectors, two boundaries: the first begins at the start/finish line, which is not
        // a sector boundary.
        #expect(renderer(params).marks.boundaries.count == 2)
    }

    // MARK: - Corners

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
        #expect(panel.outlineRuns(count: 50).count == 1)
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
