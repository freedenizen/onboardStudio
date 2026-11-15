import Foundation
import Testing

@testable import TelemetryKit

/// Laps the driver says do not count (#554): never the best, never in the optimal or the rolling
/// lap, not in the consistency, and with no marks everything reads as it did.
@Suite("Laps that do not count")
struct LapMarksTests {
    static let g = SyntheticTrack.geometry()

    /// Three laps; lap 2 is quicker than the others everywhere, as a cut or a lap behind nobody
    /// on a cleared track would be.
    static let quickSecond: TelemetrySession = {
        var session = SyntheticTrack.session(laps: 3) { lap, _ in lap == 1 ? 1.2 : 1 }
        session.sectors = Sectors.analyse(mode: .equalDistance(count: 3), session: session)
        return session
    }()

    /// Three laps, three equal sectors, lap k quickest in sector k.
    static let sectored: TelemetrySession = {
        var session = SyntheticTrack.session(laps: 3) { lap, into in
            Int(into / (g.lapLength / 3)) == lap ? 1.2 : 1
        }
        session.sectors = Sectors.analyse(mode: .equalDistance(count: 3), session: session)
        return session
    }()

    static func marking(_ session: TelemetrySession, _ numbers: [Int], as reason: LapMark.Reason = .offTrack)
        -> TelemetrySession
    {
        var marked = session
        for number in numbers {
            if let lap = session.laps.first(where: { $0.number == number }) {
                marked.lapMarks = marked.lapMarks.marking(lap, as: reason)
            }
        }
        return marked
    }

    @Test func withoutMarksEveryReadingIsUnchanged() throws {
        let session = Self.quickSecond
        #expect(session.lapMarks.isEmpty)
        #expect(session.countedSectors == session.sectors)
        #expect(LapDeltas.sessionBest(in: session)?.number == 2)
        #expect(SessionStats(session: session).bestLap?.number == 2)
        #expect(session.laps.allSatisfy { session.counts($0) })
        #expect(session.laps.counting(in: session) == session.laps)
    }

    @Test func aLapLeftOutIsNeverTheBest() throws {
        let session = Self.marking(Self.quickSecond, [2])
        let best = try #require(LapDeltas.sessionBest(in: session))
        #expect(best.number != 2)
        let stats = SessionStats(session: session)
        #expect(stats.bestLap?.number == best.number)
        // Still a complete lap of the session: counted in the laps, only not in the figures.
        #expect(stats.completeLaps == 3)
        // The coaching's best-lap reference is the best that counts.
        #expect(CoachingReference.sessionBest.resolve(in: session)?.label == "Lap \(best.number)")
        // One lap's stats are measured against the best that counts.
        let lap2 = session.laps[1]
        let delta = try #require(SessionStats(lap: lap2, in: session).deltaToBest)
        #expect(delta < 0)
    }

    @Test func theOptimalLapIsSplicedOnlyFromLapsThatCount() throws {
        let plain = SessionStats(session: Self.sectored)
        #expect(plain.optimalSources == [1, 2, 3])
        let session = Self.marking(Self.sectored, [2], as: .flag)
        let stats = SessionStats(session: session)
        #expect(!stats.optimalSources.contains(2))
        #expect(stats.optimalSources.count >= 1)
        let optimal = try #require(stats.optimalLap)
        let before = try #require(plain.optimalLap)
        #expect(optimal > before + 0.1, "lap 2's quick sector no longer counts: \(optimal) vs \(before)")
        // The coaching's optimal lap is cut from the same laps.
        let profile = try #require(CoachingReference.compositeOptimal.resolve(in: session))
        #expect(!profile.pieces.map(\.lapNumber).contains(2))
        #expect(abs(profile.duration - optimal) < 1e-6)
        // The session's own sectors are left as read: the Sector Times panel renders every lap.
        #expect(session.sectors?.laps.map(\.lapNumber) == [1, 2, 3])
        #expect(session.countedSectors?.laps.map(\.lapNumber) == [1, 3])
    }

    @Test func theRollingLapNeverRunsThroughALapLeftOut() throws {
        let plain = try #require(RollingLap.fastestWindow(in: Self.quickSecond))
        let lap2 = Self.quickSecond.laps[1]
        let lap2End = try #require(lap2.end)
        #expect(plain.start < lap2End && lap2.start < plain.end, "the quick lap holds the rolling lap")
        let session = Self.marking(Self.quickSecond, [2])
        let window = try #require(RollingLap.fastestWindow(in: session))
        #expect(!(window.start < lap2End && lap2.start < window.end))
        #expect(window.duration > plain.duration)
    }

    @Test func consistencyLeavesTheLapOut() throws {
        let session = CoachingAnalysisTests.session
        let detected = CornerDetector.corners(of: try #require(LapProfile(lap: session.laps[0], in: session)))
        let all = try #require(ConsistencyStats.measure(in: session, corners: detected))
        #expect(all.lapCount == 4)
        let one = try #require(
            ConsistencyStats.measure(in: Self.marking(session, [1], as: .traffic), corners: detected))
        #expect(one.lapCount == 3)
        // Two left out leaves two laps, too few to call anything a pattern.
        #expect(ConsistencyStats.measure(in: Self.marking(session, [1, 3]), corners: detected) == nil)
    }

    @Test func theDefaultLapIsOneThatCounts() throws {
        let session = Self.marking(Self.quickSecond, [2])
        let quickest = try #require(session.laps.quickest(excluding: nil, in: session))
        #expect(quickest.number != 2)
        // With every lap left out the quickest is still offered: something has to be read.
        let all = Self.marking(Self.quickSecond, [1, 2, 3])
        #expect(all.laps.quickest(excluding: nil, in: all)?.number == 2)
    }

    @Test func aMarkStaysWithItsDrivingWhenTheLapsAreReadAgain() throws {
        let session = Self.quickSecond
        let lap2 = session.laps[1]
        let mark = LapMark(lap: lap2, reason: .traffic)
        let end = try #require(lap2.end)
        #expect(abs(mark.time - (lap2.start + end) / 2) < 1e-9)
        // The same driving numbered from 0, as a start/finish line set later numbers it.
        var renumbered = session
        renumbered.laps = session.laps.map {
            Lap(number: $0.number - 1, start: $0.start, end: $0.end, isComplete: $0.isComplete)
        }
        renumbered.lapMarks = [mark]
        #expect(renumbered.laps.filter { !renumbered.counts($0) }.map(\.number) == [1])
    }

    @Test func markingReplacesAndClears() throws {
        let lap = Self.quickSecond.laps[1]
        let traffic = [LapMark]().marking(lap, as: .traffic)
        #expect(traffic.count == 1)
        #expect(traffic.mark(of: lap)?.reason == .traffic)
        let flag = traffic.marking(lap, as: .flag)
        #expect(flag.count == 1)
        #expect(flag.mark(of: lap)?.reason == .flag)
        #expect(flag.marking(lap, as: nil).isEmpty)
        // A mark on another lap is left alone.
        let other = Self.quickSecond.laps[0]
        #expect(flag.marking(other, as: .other).count == 2)
    }

    @Test func reasonsReadAsWords() {
        #expect(LapMark.Reason.allCases.map(\.title) == ["Traffic", "Flag", "Off Track", "Other"])
        #expect(LapMark.Reason.offTrack.word == "off track")
    }

    @Test func marksRoundTrip() throws {
        let marks = [LapMark(time: 123.5, reason: .offTrack), LapMark(time: 240, reason: .flag)]
        let data = try JSONEncoder().encode(marks)
        #expect(try JSONDecoder().decode([LapMark].self, from: data) == marks)
    }
}
