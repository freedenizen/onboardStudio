import CoreGraphics
import CoreVideo
import Foundation
import ProjectModel
import TelemetryKit
import Testing

@testable import RenderKit

/// Three laps of a 900 m circuit, built so the sector times say something.
///
/// Sectors are the three 300 m thirds. Lap 2 is quick through S1 and slow through S2; lap 3 is
/// the quickest lap but the quickest only in S2 and S3. So the best sectors come from two
/// different laps, the theoretical lap (25 s) beats every lap actually driven (27 s), and a
/// delta has a sign either way depending on what it is measured against.
///
/// | | S1 | S2 | S3 | Lap |
/// |---|---|---|---|---|
/// | Lap 1 | 10 | 10 | 10 | 30 |
/// | Lap 2 | **8** | 12 | 10 | 30 |
/// | Lap 3 | 10 | **9** | **8** | 27 |
enum SectorSession {
    static let sectorLength = 300.0
    /// Seconds each lap spent in each sector.
    static let plan: [[Double]] = [[10, 10, 10], [8, 12, 10], [10, 9, 8]]
    /// Lap 3, six seconds into S3 (which began at 79 s): S1 lost time, S2 gained it, S3 is running.
    static let lateOnTheQuickLap = 85.0

    static let session: TelemetrySession = {
        var times: [Double] = []
        var distances: [Double] = []
        var laps: [Lap] = []
        var now = 0.0
        var travelled = 0.0
        for (index, lap) in plan.enumerated() {
            let start = now
            for seconds in lap {
                let speed = sectorLength / seconds
                var elapsed = 0.0
                while elapsed < seconds {
                    times.append(now + elapsed)
                    distances.append(travelled + speed * elapsed)
                    elapsed += 0.1
                }
                now += seconds
                travelled += sectorLength
            }
            laps.append(Lap(number: index + 1, start: start, end: now, isComplete: true))
        }
        times.append(now)
        distances.append(travelled)
        var session = TelemetrySession(
            info: SessionInfo(sourceFormat: "synthetic"),
            channels: [Channel(role: .distance, name: "d", unit: .meters, times: times, values: distances)],
            laps: laps)
        session.sectors = Sectors.analyse(mode: .equalDistance(count: 3), session: session)
        return session
    }()
}

@Suite("Sector panel")
struct SectorPanelTests {
    let frame = UnitRect(x: 0.05, y: 0.35, width: 0.9, height: 0.3)

    func renderer(_ params: SectorPanelParams = SectorPanelParams(), session: TelemetrySession = SectorSession.session)
        -> SectorPanelRenderer
    {
        SectorPanelRenderer(
            context: ObjectContext(
                objectID: DisplayObjectID(UUID(uuidString: "00000000-0000-0000-0000-000000000003") ?? UUID()),
                frame: frame, opacity: 1, sampler: TelemetrySampler(session: session), sync: .identity,
                cache: RenderCache()),
            params: params)
    }

    @Test func theSessionUnderTestHasSectors() throws {
        let analysis = try #require(SectorSession.session.sectors)
        #expect(analysis.count == 3)
        #expect(analysis.laps.count >= 2)
    }

    @Test func oneCellPerSectorPlusTheTheoreticalLap() throws {
        let cells = renderer().cells(at: 45)
        #expect(cells.count == 4)
        #expect(cells.map(\.label) == ["S1", "S2", "S3", "Optimal"])
        #expect(try #require(cells.last?.time) > 0)
    }

    @Test func theTheoreticalLapCanBeTurnedOff() {
        var params = SectorPanelParams()
        params.showTheoretical = false
        #expect(renderer(params).cells(at: 45).count == 3)
    }

    @Test func theSectorInProgressRunsAndTheOnesAfterItAreBlank() throws {
        // Lap 2 runs 30…60 s and its S1 ends at 38 s, so at 35 s the car is still in S1.
        let cells = renderer().cells(at: 35)
        let current = try #require(cells.first { $0.isCurrent })
        #expect(current.label == "S1")
        #expect(try #require(current.time) > 0)
        // A sector in progress has no delta yet, and the ones after it have no time.
        #expect(current.delta == nil)
        #expect(cells[1].time == nil)
        #expect(cells[2].time == nil)
        #expect(cells.filter(\.isCurrent).count == 1)
    }

    @Test func aFinishedSectorGetsATimeAndADelta() throws {
        // 55 s is inside lap 2's S3, so S1 and S2 are behind us.
        let cells = renderer().cells(at: 55)
        #expect(cells[0].time != nil)
        #expect(cells[0].delta != nil)
        #expect(cells[2].isCurrent)
        #expect(cells[2].delta == nil)
    }

    @Test func theBestSectorReferenceGivesANonPositiveDeltaOnTheLapThatSetIt() throws {
        let analysis = try #require(SectorSession.session.sectors)
        let best = try #require(analysis.best[0])
        // Ask on the lap that owns the best S1: its delta against "best sector" must be zero.
        let lap = try #require(SectorSession.session.laps.first { $0.number == best.lapNumber })
        let cells = renderer().cells(at: (lap.start + (lap.end ?? lap.start)) / 2)
        #expect(abs(try #require(cells[0].delta)) < 1e-9)
    }

    @Test func comparingWithTheLapBeforeHasNothingToSayOnTheFirstLap() throws {
        var params = SectorPanelParams()
        params.reference = .previousLap
        // Lap 1 is the first lap, so there is no earlier lap to compare its sectors with.
        let cells = renderer(params).cells(at: 15)
        #expect(cells[0].time != nil)
        #expect(cells[0].delta == nil)
        // On lap 1 the comparison exists.
        #expect(renderer(params).cells(at: 45)[0].delta != nil)
    }

    @Test func theLapJustFinishedIsHeldSoItsLastSectorCanBeRead() throws {
        // Lap 2 ends at 60 s. Two seconds later the panel still shows lap 2, complete: S3 is
        // only ever finished for the instant the car crosses, so without the hold a third of
        // every lap is unreadable.
        let cells = renderer().cells(at: 62)
        #expect(cells.allSatisfy { !$0.isCurrent })
        #expect(cells[0].time == 8)
        #expect(cells[1].time == 12)
        #expect(cells[2].time == 10)
        #expect(cells[2].delta != nil)
    }

    @Test func theHoldEndsAndTheNewLapTakesOver() throws {
        // Default hold is five seconds, so at 66 s lap 3 is showing and is one sector in.
        let cells = renderer().cells(at: 66)
        #expect(cells[0].isCurrent)
        #expect(cells[1].time == nil)
    }

    @Test func theHoldCanBeTurnedOff() throws {
        var params = SectorPanelParams()
        params.holdPreviousSeconds = 0
        let cells = renderer(params).cells(at: 62)
        #expect(cells[0].isCurrent)
        #expect(cells[2].time == nil)
    }

    @Test func thereIsNothingToHoldOnTheFirstLap() {
        // Two seconds into lap 1 there is no earlier lap, so the panel shows lap 1 in progress.
        #expect(renderer().cells(at: 2)[0].isCurrent)
    }

    @Test func aSessionWithoutSectorsDrawsNothing() {
        #expect(renderer(SectorPanelParams(), session: SyntheticSession.session).cells(at: 5).isEmpty)
    }

    @Test func aSingleSectorDrawsNothingBecauseThatIsJustTheLap() throws {
        var session = SectorSession.session
        session.sectors = Sectors.analyse(mode: .equalDistance(count: 1), session: session)
        #expect(try #require(session.sectors).count == 1)
        #expect(renderer(SectorPanelParams(), session: session).cells(at: 45).isEmpty)
    }

    @Test func outsideEveryLapThereIsNothingToShow() {
        #expect(renderer().cells(at: -5).isEmpty)
    }

    @Test func aDeltaThatRoundsToZeroIsNeitherAheadNorBehind() {
        let params = SectorPanelParams()
        let panel = renderer(params)
        // The lap holding the best sector always shows 0.00 against it; calling that a loss on
        // the last digit of floating point would paint the best lap red.
        #expect(panel.colour(for: 0) == params.textColor)
        #expect(panel.colour(for: 0.001) == params.textColor)
        #expect(panel.colour(for: -0.001) == params.textColor)
        #expect(panel.colour(for: 0.5) == params.behindColor)
        #expect(panel.colour(for: -0.5) == params.aheadColor)
    }

    @Test func sectorTimesAndDeltas() throws {
        // Lap 3 against lap 2: S1 lost two seconds, S2 gained three, and S3 is still running.
        var params = SectorPanelParams()
        params.reference = .previousLap
        try GoldenImage.assertMatches(
            try render(params, time: SectorSession.lateOnTheQuickLap), named: "sector-panel-lap3")
    }

    @Test func theTheoreticalLapKeepsItsTimeInTheDeltaOnlyMode() throws {
        // It is a lap time, not a comparison, so it has no delta to draw in its place. Without
        // this its column is a heading over permanent blank space.
        var params = SectorPanelParams()
        params.display = .delta
        let cells = renderer(params).cells(at: SectorSession.lateOnTheQuickLap)
        let theoretical = try #require(cells.last)
        #expect(theoretical.isTheoretical)
        #expect(theoretical.delta == nil)
        #expect(try #require(theoretical.time) > 0)
        #expect(cells.dropLast().allSatisfy { !$0.isTheoretical })
    }

    @Test func deltasOnly() throws {
        // Against the best sector: S1 is two seconds off it, and S2 holds it, so S2's 0.00 is
        // drawn in the text colour rather than red. The theoretical lap keeps its time.
        var params = SectorPanelParams()
        params.display = .delta
        try GoldenImage.assertMatches(
            try render(params, time: SectorSession.lateOnTheQuickLap), named: "sector-panel-deltas-lap3")
    }

    func render(_ params: SectorPanelParams, time: Double) throws -> CVPixelBuffer {
        let plan = RenderPlan(
            outputWidth: 600, outputHeight: 200, frameRate: 30, videoLayers: [], overlays: [renderer(params)])
        return try FrameCompositor(plan: plan).renderFrame(sources: [:], time: time)
    }
}
