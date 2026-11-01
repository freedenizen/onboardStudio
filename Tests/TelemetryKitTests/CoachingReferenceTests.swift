import Foundation
import Testing

@testable import TelemetryKit

@Suite("Coaching references")
struct CoachingReferenceTests {
    static let g = SyntheticTrack.geometry()

    /// Three laps whose fast half alternates: the first lap is slow then fast, the second fast
    /// then slow, the third slow then fast. No whole lap is quick, but the fast second half of
    /// lap 1 and the fast first half of lap 2 make one quick lap-length stretch across the line.
    static let straddling = SyntheticTrack.session(laps: 3) { lap, into in
        let secondHalf = into >= g.lapLength / 2
        return (lap == 1) != secondHalf ? 1 : 0.5
    }

    @Test func theFastestRollingLapCrossesTheLine() throws {
        let session = Self.straddling
        let window = try #require(RollingLap.fastestWindow(in: session))
        let halfway = session.laps[0].start + (Self.g.lapLength / 2) / 12.5
        #expect(abs(window.start - halfway) < 0.5, "started \(window.start - session.laps[0].start) s into lap 1")
        #expect(abs(window.duration - Self.g.lapLength / 25) < 0.3)
        // Quicker than any whole lap.
        let bestLap = try #require(LapDeltas.sessionBest(in: session)?.duration)
        #expect(window.duration < bestLap - 10)

        let profile = try #require(RollingLap.profile(in: session))
        #expect(profile.label == "Fastest rolling lap")
        #expect(abs(profile.lengthMeters - Self.g.lapLength) < 1)
        #expect(abs(profile.duration - window.duration) < 0.3)
        // Re-based to the line: the piece after the line (lap 2's first half) comes first.
        #expect(profile.pieces.map(\.lapNumber) == [2, 1])
        #expect(profile.isSpliced)
        #expect(profile.seams.count == 1)
        #expect(abs((profile.seams.first ?? 0) - Self.g.lapLength / 2) < 2)
        // Fast the whole way round, and the clock runs on across the join.
        for distance in stride(from: 0.0, through: profile.lengthMeters, by: 100) {
            #expect(abs((profile.value(of: .speed, atDistance: distance) ?? 0) - 25) < 0.5, "at \(distance)")
        }
        #expect(abs(profile.elapsed(atDistance: Self.g.lapLength / 2) - profile.duration / 2) < 0.3)
        let elapsed = profile.elapsed
        #expect(zip(elapsed, elapsed.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func aRollingLapWithinOneLapIsThatLap() throws {
        // Steady laps: every window is the same, so the first complete lap wins and is one piece.
        let session = SyntheticTrack.session(laps: 2)
        let profile = try #require(RollingLap.profile(in: session))
        #expect(!profile.isSpliced)
        #expect(profile.pieces.map(\.lapNumber) == [1])
        let lap = try #require(LapProfile(lap: session.laps[0], in: session))
        #expect(abs(profile.duration - lap.duration) < 1e-6)
    }

    @Test func nothingRollsWithoutCompleteLaps() {
        let empty = TelemetrySession(info: SessionInfo(sourceFormat: "test"), channels: [])
        #expect(RollingLap.fastestWindow(in: empty) == nil)
        var session = SyntheticTrack.session(laps: 1)
        session.laps = [Lap(number: 1, start: 0, end: nil, isComplete: false)]
        #expect(RollingLap.fastestWindow(in: session) == nil)
        #expect(CoachingReference.fastestRolling.resolve(in: session) == nil)
    }

    /// Three laps, three equal sectors, lap k quickest in sector k.
    static let sectored: TelemetrySession = {
        var session = SyntheticTrack.session(laps: 3) { lap, into in
            Int(into / (g.lapLength / 3)) == lap ? 1.2 : 1
        }
        session.sectors = Sectors.analyse(mode: .equalDistance(count: 3), session: session)
        return session
    }()

    @Test func theOptimalLapIsTheBestSectorsJoined() throws {
        let session = Self.sectored
        let analysis = try #require(session.sectors)
        #expect(analysis.best.map { $0?.lapNumber } == [1, 2, 3])
        let optimal = try #require(CompositeLap.optimal(in: session, analysis: analysis))
        #expect(optimal.label == "Optimal lap (spliced)")
        #expect(optimal.pieces.map(\.lapNumber) == [1, 2, 3])
        #expect(optimal.seams.count == 2)
        #expect(abs((optimal.seams.first ?? 0) - Self.g.lapLength / 3) < 1e-6)
        let theoretical = try #require(analysis.theoreticalLapTime)
        #expect(abs(optimal.duration - theoretical) < 1e-6, "\(optimal.duration) vs \(theoretical)")
        #expect(abs(optimal.lengthMeters - Self.g.lapLength) < 1e-6)
        // Quick everywhere: each sector came from the lap that was quick there.
        for distance in stride(from: 10.0, to: optimal.lengthMeters, by: 50) {
            #expect(abs((optimal.value(of: .speed, atDistance: distance) ?? 0) - 30) < 0.5, "at \(distance)")
        }
        // Position is continuous across the joins: both laps were at the same place.
        let seam = try #require(optimal.seams.first)
        let before = try #require(optimal.position(atDistance: seam - 2))
        let after = try #require(optimal.position(atDistance: seam + 2))
        #expect(
            DerivedChannels.distance(
                lat1: before.latitude, lon1: before.longitude, lat2: after.latitude, lon2: after.longitude) < 6)
        // Every real lap is behind the optimal lap everywhere it was not the quick one.
        let lap2 = try #require(LapProfile(lap: session.laps[1], in: session))
        let trace = try #require(LapDeltaTrace(lap: lap2, reference: optimal))
        #expect(trace.total > 0)
        #expect(abs(trace.loss(from: Self.g.lapLength / 3, to: 2 * Self.g.lapLength / 3)) < 0.05)
    }

    @Test func referencesResolveToProfiles() throws {
        let session = Self.sectored
        let best = try #require(CoachingReference.sessionBest.resolve(in: session))
        #expect(best.label == "Lap \(LapDeltas.sessionBest(in: session)?.number ?? 0)")
        #expect(CoachingReference.lap(2).resolve(in: session)?.label == "Lap 2")
        #expect(CoachingReference.lap(9).resolve(in: session) == nil)
        let optimal = try #require(CoachingReference.compositeOptimal.resolve(in: session))
        #expect(optimal.isSpliced)
        // Without sectors on the session, corner-aware sectors are made for it.
        var plain = session
        plain.sectors = nil
        #expect(CoachingReference.compositeOptimal.resolve(in: plain) != nil)
        #expect(CoachingReference.fastestRolling.resolve(in: session) != nil)
        #expect(CoachingReference.lap(3).displayName == "Lap 3")
        #expect(CoachingReference.fastestRolling.phrase == "the rolling lap")
    }

    @Test func spliceCutsAreInProfileOrderWithTheClockRunningOn() throws {
        let session = SyntheticTrack.session(laps: 2)
        let lap1 = session.laps[0]
        let lap2 = session.laps[1]
        let third = Self.g.lapLength / 3
        let profile = try #require(
            LapProfile.spliced(
                [.init(lap: lap2, from: 0, to: third), .init(lap: lap1, from: third, to: Self.g.lapLength)],
                in: session, label: "x"))
        #expect(profile.pieces.count == 2)
        #expect(profile.pieces[1].range.lowerBound == profile.pieces[0].range.upperBound)
        #expect(abs(profile.duration - Self.g.lapLength / 25) < 0.1)
        #expect(profile.distances[1] - profile.distances[0] == 2)
        #expect(LapProfile.spliced([], in: session, label: "x") == nil)
        #expect(LapProfile.spliced([.init(lap: lap1, from: 10, to: 12)], in: session, label: "x") == nil)
    }
}
