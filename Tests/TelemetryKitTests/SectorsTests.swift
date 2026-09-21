import Foundation
import Testing

@testable import TelemetryKit

@Suite("Sector layout")
struct SectorLayoutTests {
    static let geometry = SyntheticTrack.geometry()

    @Test func equalDistanceSplitsTheReferenceLap() throws {
        let session = SyntheticTrack.session()
        let layout = try #require(Sectors.layout(mode: .equalDistance(count: 3), session: session))
        #expect(layout.count == 3)
        #expect(abs(layout.lapLengthMeters - Self.geometry.lapLength) < 1)
        let third = Self.geometry.lapLength / 3
        #expect(abs(layout.boundaryDistances[0] - third) < 1)
        #expect(abs(layout.boundaryDistances[1] - 2 * third) < 1)
    }

    @Test func oneSectorHasNoBoundaries() throws {
        let session = SyntheticTrack.session()
        let layout = try #require(Sectors.layout(mode: .equalDistance(count: 1), session: session))
        #expect(layout.boundaryDistances.isEmpty)
        #expect(layout.count == 1)
    }

    @Test func cornerAwareMovesTheBoundaryOntoTheStraight() throws {
        let session = SyntheticTrack.session()
        // Two sectors: the single boundary belongs on the one straight between the two bends,
        // not halfway round, which is inside the first bend's exit.
        let layout = try #require(Sectors.layout(mode: .cornerAware(count: 2), session: session))
        #expect(layout.boundaryDistances.count == 1)
        #expect(abs(layout.boundaryDistances[0] - Self.geometry.backStraightMidpoint) < 20)
        #expect(!Self.geometry.firstBend.contains(layout.boundaryDistances[0]))
        #expect(!Self.geometry.secondBend.contains(layout.boundaryDistances[0]))
    }

    @Test func cornerAwareFallsBackToEqualWhenThereAreNoCorners() {
        // Straights only: nothing to avoid, so the equal split stands.
        #expect(Sectors.cornerAwareBoundaries(count: 3, length: 900, straights: []) == [300, 600])
    }

    @Test func aBoundaryNeverMovesMoreThanHalfASector() {
        // Three sectors of 300 m: a boundary may move at most 150 m. The only straight is 290 m
        // from the first boundary and 590 m from the second, so neither reaches it and the equal
        // split stands.
        #expect(Sectors.cornerAwareBoundaries(count: 3, length: 900, straights: [10]) == [300, 600])
        // A straight 100 m before the second boundary is within its reach but not the first's.
        #expect(Sectors.cornerAwareBoundaries(count: 3, length: 900, straights: [500]) == [300, 500])
    }

    @Test func eachStraightTakesAtMostOneBoundary() {
        // Both straights sit beside the first boundary. It takes the nearer one, and the second
        // boundary is not dragged 280 m back to the other.
        #expect(Sectors.cornerAwareBoundaries(count: 3, length: 900, straights: [310, 320]) == [310, 600])
        // One straight within reach of each boundary: both move.
        #expect(Sectors.cornerAwareBoundaries(count: 3, length: 900, straights: [320, 580]) == [320, 580])
    }

    @Test func manualGatesBecomeTheDistancesTheReferenceLapCrossedThem() throws {
        let session = SyntheticTrack.session()
        // A gate on the back straight, which the circuit runs westward.
        let midpoint = Self.geometry.backStraightMidpoint
        let point = SyntheticTrack.point(at: midpoint, geometry: Self.geometry)
        let line = FinishLine(
            latitude: SyntheticTrack.origin.latitude + point.y / 110_540,
            longitude: SyntheticTrack.origin.longitude
                + point.x / (111_320 * cos(SyntheticTrack.origin.latitude * .pi / 180)),
            headingDegrees: 270, halfWidthMeters: 30)
        let layout = try #require(Sectors.layout(mode: .manual(lines: [line]), session: session))
        #expect(layout.count == 2)
        #expect(abs(layout.boundaryDistances[0] - midpoint) < 5)
    }

    @Test func aGateTheReferenceLapNeverCrossedIsDropped() throws {
        let session = SyntheticTrack.session()
        let far = FinishLine(latitude: 0, longitude: 0, halfWidthMeters: 25)
        let layout = try #require(Sectors.layout(mode: .manual(lines: [far]), session: session))
        #expect(layout.boundaryDistances.isEmpty)
    }

    @Test func boundariesAreSortedAndDeduplicated() {
        #expect(Sectors.tidied([600, 300, 300.5, -10, 1000], length: 900) == [300, 600])
    }

    @Test func aSessionWithoutLapsHasNoLayout() {
        let session = TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [Channel(role: .distance, name: "d", unit: .meters, times: [0, 1], values: [0, 10])])
        #expect(Sectors.layout(mode: .equalDistance(count: 3), session: session) == nil)
    }

    @Test func aSessionWithoutDistanceHasNoLayout() {
        let session = TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [Channel(role: .speed, name: "s", unit: .metersPerSecond, times: [0, 10], values: [5, 5])],
            laps: [Lap(number: 1, start: 0, end: 10, isComplete: true)])
        #expect(Sectors.layout(mode: .equalDistance(count: 3), session: session) == nil)
    }

    @Test func whichSectorADistanceFallsIn() {
        let layout = SectorLayout(boundaryDistances: [300, 600], lapLengthMeters: 900, referenceLapNumber: 1)
        #expect(layout.sector(atDistanceIntoLap: 0) == 0)
        #expect(layout.sector(atDistanceIntoLap: 299) == 0)
        #expect(layout.sector(atDistanceIntoLap: 300) == 1)
        #expect(layout.sector(atDistanceIntoLap: 899) == 2)
        // A lap driven wider than the reference runs past the end and is still in the last sector.
        #expect(layout.sector(atDistanceIntoLap: 950) == 2)
        #expect(layout.range(of: 0) == 0...300)
        #expect(layout.range(of: 2) == 600...900)
        #expect(SectorLayout.name(of: 0) == "S1")
    }
}

@Suite("Sector times")
struct SectorTimesTests {
    static let geometry = SyntheticTrack.geometry()

    /// Three laps: the second is 10% quicker through the first third and normal elsewhere, so
    /// the best S1 and the best lap belong to different laps.
    static let session = SyntheticTrack.session(laps: 3) { lap, into in
        lap == 1 && into < SyntheticTrack.geometry().lapLength / 3 ? 1.1 : 1
    }

    @Test func everySectorOfEveryLapIsTimed() throws {
        let analysis = try #require(Sectors.analyse(mode: .equalDistance(count: 3), session: Self.session))
        #expect(analysis.laps.count == 3)
        for lap in analysis.laps {
            #expect(lap.times.count == 3)
            #expect(lap.times.allSatisfy { $0 != nil })
        }
    }

    @Test func sectorsAddUpToTheLapTime() throws {
        let analysis = try #require(Sectors.analyse(mode: .equalDistance(count: 3), session: Self.session))
        for (lap, sectors) in zip(Self.session.laps, analysis.laps) {
            let total = try #require(sectors.total)
            #expect(abs(total - (lap.duration ?? 0)) < 0.05)
        }
    }

    @Test func theQuickerSectorWinsItsColumnOnly() throws {
        let analysis = try #require(Sectors.analyse(mode: .equalDistance(count: 3), session: Self.session))
        let best = analysis.best
        #expect(best[0]?.lapNumber == 2)  // lap 2 was 10% quicker through S1
        // The other two sectors were driven identically on every lap, so no lap stands out and
        // which one holds the best is decided by the last millisecond of arithmetic.
        for sector in [1, 2] {
            let times = analysis.laps.compactMap { $0.times[sector] }
            #expect(times.count == 3)
            let spread = try #require(times.max()) - #require(times.min())
            #expect(spread < 0.02)
        }
        // Lap 2 gains its time in S1 alone and is not the quickest anywhere else.
        #expect(best[1]?.lapNumber != 2 || best[2]?.lapNumber != 2)
    }

    @Test func theTheoreticalLapIsNoSlowerThanTheBestLap() throws {
        let analysis = try #require(Sectors.analyse(mode: .equalDistance(count: 3), session: Self.session))
        let theoretical = try #require(analysis.theoreticalLapTime)
        let bestLap = try #require(Self.session.laps.compactMap(\.duration).min())
        #expect(theoretical <= bestLap + 1e-6)
        // Here it equals the quick lap exactly, because one lap holds every best sector.
        #expect(abs(theoretical - bestLap) < 0.05)
    }

    @Test func deltaToBestIsZeroOnTheLapThatSetIt() throws {
        let analysis = try #require(Sectors.analyse(mode: .equalDistance(count: 3), session: Self.session))
        #expect(abs(try #require(analysis.deltaToBest(sector: 0, lapNumber: 2))) < 1e-9)
        let slower = try #require(analysis.deltaToBest(sector: 0, lapNumber: 1))
        #expect(slower > 0)
        #expect(analysis.deltaToBest(sector: 0, lapNumber: 99) == nil)
        #expect(analysis.deltaToBest(sector: 9, lapNumber: 1) == nil)
    }

    @Test func anUnfinishedLapTimesOnlyTheSectorsItCompleted() throws {
        let full = SyntheticTrack.session(laps: 2)
        // Cut the last lap off a third of the way round.
        var session = full
        let lastStart = full.laps[1].start
        let stop = lastStart + (full.laps[0].duration ?? 0) * 0.4
        session.laps = [full.laps[0], Lap(number: 2, start: lastStart, end: stop, isComplete: false)]
        let layout = try #require(Sectors.layout(mode: .equalDistance(count: 3), session: session))
        let times = Sectors.times(for: session.laps[1], layout: layout, session: session)
        #expect(times[0] != nil)
        #expect(times[1] == nil)
        #expect(times[2] == nil)
    }

    @Test func aLapThatNeverReachesTheFirstBoundaryIsLeftOut() throws {
        // A car sitting in the paddock covers no distance, so it has no sector times and does
        // not compete for a best.
        let full = SyntheticTrack.session(laps: 2)
        var session = full
        session.laps =
            [Lap(number: 0, start: full.laps[0].start, end: full.laps[0].start + 1, isComplete: false)]
            + full.laps
        let analysis = try #require(Sectors.analyse(mode: .equalDistance(count: 3), session: session))
        #expect(!analysis.laps.contains { $0.lapNumber == 0 })
    }

    @Test func statusReportsTheSectorInProgress() throws {
        let analysis = try #require(Sectors.analyse(mode: .equalDistance(count: 3), session: Self.session))
        let lap = Self.session.laps[0]
        let duration = try #require(lap.duration)
        let status = try #require(analysis.status(at: lap.start + duration / 2, session: Self.session))
        #expect(status.lapNumber == 1)
        #expect(status.sectorIndex == 1)
        // S1 is behind us and timed; S2 is in progress and S3 has not started.
        #expect(status.times[0] != nil)
        #expect(status.times[1] == nil)
        #expect(status.times[2] == nil)
        let s1 = try #require(status.times[0])
        #expect(abs(status.elapsedInSector - (duration / 2 - s1)) < 0.05)
    }

    @Test func statusOutsideEveryLapIsNil() throws {
        let analysis = try #require(Sectors.analyse(mode: .equalDistance(count: 3), session: Self.session))
        #expect(analysis.status(at: -10, session: Self.session) == nil)
    }
}

@Suite("Sectors on an imported session")
struct SectorSessionBuilderTests {
    @Test func buildingASessionMeasuresSectors() throws {
        var table = RawTable(info: SessionInfo(sourceFormat: "test"), times: [], columns: [])
        let source = SyntheticTrack.session(laps: 2)
        let latitude = try #require(source[.latitude])
        let longitude = try #require(source[.longitude])
        table.times = latitude.times
        table.columns = [
            RawColumn(name: "Latitude", unit: .degrees, suggestedRole: .latitude, values: latitude.values),
            RawColumn(name: "Longitude", unit: .degrees, suggestedRole: .longitude, values: longitude.values),
        ]
        table.lapMarkers = source.laps.enumerated().map { RawLapMarker(number: $0.offset + 1, time: $0.element.start) }
        let session = SessionBuilder.build(table)
        let analysis = try #require(session.sectors)
        #expect(analysis.layout.count == 3)
        #expect(analysis.laps.count >= 1)
    }

    @Test func aSessionWithoutPositionHasNoSectors() {
        let table = RawTable(
            info: SessionInfo(sourceFormat: "test"), times: [0, 1, 2],
            columns: [
                RawColumn(name: "Speed", unit: .metersPerSecond, suggestedRole: .speed, values: [10, 10, 10])
            ])
        #expect(SessionBuilder.build(table).sectors == nil)
    }
}
