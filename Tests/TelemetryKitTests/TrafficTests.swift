import Foundation
import Testing

@testable import TelemetryKit

/// Traffic and flag marks (#571): the corners they cover are not coached and do not count towards
/// consistency, and everything else reads as it did.
@Suite("Traffic marks")
struct TrafficTests {
    /// Fast, slow, fast, fast — lap 2 is held up in both corners by construction.
    static let session = CoachingAnalysisTests.session

    /// The stretch of session time corner `index` was read over on lap `lapIndex`.
    static func times(ofCorner index: Int, lap lapIndex: Int, in session: TelemetrySession) throws -> ClosedRange<
        Double
    > {
        let analysis = try #require(
            CoachingAnalysis.analyse(lap: session.laps[lapIndex], reference: .sessionBest, in: session))
        return analysis.sessionTimes(of: analysis.corners[index])
    }

    static func marked(_ spans: [TrafficSpan], in session: TelemetrySession = session) -> TelemetrySession {
        var marked = session
        marked.traffic = spans
        return marked
    }

    @Test func withoutMarksTheReadingIsUnchanged() throws {
        let plain = try #require(
            CoachingAnalysis.analyse(lap: Self.session.laps[1], reference: .sessionBest, in: Self.session))
        #expect(plain.corners.allSatisfy { $0.traffic == nil })
        #expect(plain.trafficLoss == 0)
        #expect(!plain.headline(lapNumber: 2, units: .metric).contains("traffic"))
        #expect(!plain.warnings.contains { if case .traffic = $0 { true } else { false } })
        // A mark on a lap that is neither this one nor the reference leaves the reading alone.
        let best = try #require(LapDeltas.sessionBest(in: Self.session)?.number)
        let other = try #require([0, 2, 3].first { Self.session.laps[$0].number != best })
        let elsewhere = try Self.times(ofCorner: 0, lap: other, in: Self.session)
        let session = Self.marked([TrafficSpan(start: elsewhere.lowerBound, end: elsewhere.upperBound)])
        let read = try #require(CoachingAnalysis.analyse(lap: session.laps[1], reference: .sessionBest, in: session))
        #expect(read.opportunities.map(\.corner.index) == plain.opportunities.map(\.corner.index))
        #expect(read.corners.allSatisfy { $0.traffic == nil })
    }

    @Test func aMarkedCornerIsNoOpportunityAndSaysWhy() throws {
        let first = try Self.times(ofCorner: 0, lap: 1, in: Self.session)
        let session = Self.marked([TrafficSpan(start: first.lowerBound, end: first.upperBound)])
        let analysis = try #require(
            CoachingAnalysis.analyse(lap: session.laps[1], reference: .sessionBest, in: session))
        let marked = analysis.corners[0]
        #expect(marked.traffic == CornerTraffic(kind: .traffic, onLap: true, onReference: false))
        #expect(analysis.corners[1].traffic == nil)
        // Only the second corner is coached.
        #expect(analysis.opportunities.map(\.corner.index) == [1])
        #expect(analysis.opportunities[0].rank == 1)
        // Its loss is still in the lap's total, and named apart in the headline.
        #expect(analysis.trafficLoss == marked.timeLost)
        let headline = analysis.headline(lapNumber: 2, units: .metric)
        #expect(headline.hasSuffix(" of it held up by traffic"))
        #expect(analysis.warnings.contains(.traffic(labels: ["1"])))
        let rows = analysis.rows(units: .metric)
        #expect(rows[0].phase == "traffic")
        #expect(rows[1].phase != "traffic")
        #expect(marked.trafficHeadline(referencePhrase: analysis.referencePhrase) == "Turn 1: held up by traffic")
    }

    @Test func aFlagReadsAsAFlag() throws {
        let both =
            try Self.times(ofCorner: 0, lap: 1, in: Self.session)
            .lowerBound...Self.times(
                ofCorner: 1, lap: 1, in: Self.session
            ).upperBound
        let session = Self.marked([TrafficSpan(start: both.lowerBound, end: both.upperBound, kind: .flag)])
        let analysis = try #require(
            CoachingAnalysis.analyse(lap: session.laps[1], reference: .sessionBest, in: session))
        #expect(analysis.opportunities.isEmpty)
        #expect(analysis.rows(units: .metric).map(\.phase) == ["flag", "flag"])
        #expect(analysis.headline(lapNumber: 2, units: .metric).hasSuffix(" of it under a flag"))
    }

    @Test func aMarkOnTheReferenceKeepsTheCornerOutToo() throws {
        let session = Self.session
        let plain = try #require(CoachingAnalysis.analyse(lap: session.laps[1], reference: .sessionBest, in: session))
        let best = try #require(session.laps.first { "Lap \($0.number)" == plain.reference.label })
        let corner = plain.corners[1]
        let range = try #require(corner.range)
        let start = best.start + plain.reference.elapsed(atDistance: range.lowerBound)
        let end = best.start + plain.reference.elapsed(atDistance: range.upperBound)
        let marked = Self.marked([TrafficSpan(start: start, end: end)])
        let analysis = try #require(
            CoachingAnalysis.analyse(lap: marked.laps[1], reference: .sessionBest, in: marked))
        #expect(analysis.corners[1].traffic == CornerTraffic(kind: .traffic, onLap: false, onReference: true))
        #expect(!analysis.opportunities.contains { $0.corner.index == 1 })
        // The lap itself was not held up, so nothing of its loss is put down to traffic.
        #expect(analysis.trafficLoss == 0)
        #expect(
            analysis.corners[1].trafficHeadline(referencePhrase: analysis.referencePhrase)
                == "Turn 2: your best lap was held up by traffic")
    }

    @Test func consistencyLeavesOutTheMarkedCornerButKeepsTheRestOfTheLap() throws {
        // Fast, fast, slow, fast: without marks the slow lap's brake points make both corners
        // inconsistent.
        let fast = CoachingFixture.fast
        let session = CoachingFixture.session(drivings: [fast, fast, CoachingFixture.slow, fast])
        let corners = CornerDetector.corners(of: try #require(LapProfile(lap: session.laps[0], in: session)))
        let plain = try #require(ConsistencyStats.measure(in: session, corners: corners))
        #expect(plain.corners.allSatisfy { !$0.isConsistent })
        let first = try Self.times(ofCorner: 0, lap: 2, in: session)
        let marked = Self.marked([TrafficSpan(start: first.lowerBound, end: first.upperBound)], in: session)
        let stats = try #require(ConsistencyStats.measure(in: marked, corners: corners))
        // The slow lap still counts, but not its first corner.
        #expect(stats.lapCount == 4)
        #expect(stats.spread(ofCorner: 0)?.lapCount == 3)
        #expect(stats.spread(ofCorner: 0)?.isConsistent == true)
        #expect(stats.spread(ofCorner: 1)?.lapCount == 4)
        #expect(stats.spread(ofCorner: 1)?.isConsistent == false)
        // A lap with a mark says nothing about lap-time consistency.
        #expect(stats.lapTimeSpread < plain.lapTimeSpread)
    }

    @Test func aLapHeldUpPastTheFlyingLimitStillCountsCornerByCorner() throws {
        // Lap 3 crawls through its first corner: far outside the 10 % a flying lap is allowed.
        let fast = CoachingFixture.fast
        var crawl = CoachingFixture.slow
        crawl.minimumSpeed = 4
        crawl.deceleration = 1.5
        crawl.acceleration = 0.5
        let session = CoachingFixture.session(drivings: [fast, fast, crawl, fast])
        let durations = session.laps.compactMap(\.duration)
        #expect(durations[2] > (durations.min() ?? 0) * 1.1)
        let corners = CornerDetector.corners(of: try #require(LapProfile(lap: session.laps[0], in: session)))
        let plain = try #require(ConsistencyStats.measure(in: session, corners: corners))
        #expect(plain.lapCount == 3)
        // Marked through both corners, its straights at the best lap's pace bring it inside.
        let lap = session.laps[2]
        let marked = Self.marked(
            [TrafficSpan(start: lap.start + 1, end: (lap.end ?? lap.start) - 1)], in: session)
        let stats = try #require(ConsistencyStats.measure(in: marked, corners: corners))
        #expect(stats.lapCount == 4)
        #expect(stats.corners.allSatisfy { $0.lapCount == 3 })
    }

    @Test func theDefaultLapIsOneNoMarkTouches() throws {
        let session = Self.session
        let complete = session.laps.filter(\.isComplete)
        let best = try #require(LapDeltas.sessionBest(in: session)?.number)
        let plain = try #require(complete.quickest(excluding: best, in: session))
        let marked = Self.marked([TrafficSpan(start: plain.start + 5, end: plain.start + 8)])
        let chosen = try #require(complete.quickest(excluding: best, in: marked))
        #expect(chosen.number != plain.number)
        #expect(chosen.number != best)
        // When every lap has a mark, the quickest is still offered.
        let all = Self.marked(complete.map { TrafficSpan(start: $0.start + 5, end: $0.start + 8) })
        #expect(complete.quickest(excluding: best, in: all)?.number == plain.number)
    }

    @Test func markingSplitsAndClears() {
        let spans = [TrafficSpan(start: 10, end: 40)]
        let middle = spans.marking(20, 30, as: nil)
        #expect(middle.map(\.start) == [10, 30])
        #expect(middle.map(\.end) == [20, 40])
        let flagged = spans.marking(35, 50, as: .flag)
        #expect(flagged.map(\.start) == [10, 35])
        #expect(flagged.map(\.kind) == [.traffic, .flag])
        #expect(spans.marking(0, 100, as: nil).isEmpty)
        #expect(spans.marking(50, 60, as: nil) == spans)
        // Backwards bounds are put the right way round.
        #expect(TrafficSpan(start: 5, end: 2).start == 2)
    }

    @Test func aSplicedProfileReadsEachPieceInItsOwnLap() throws {
        let session = Self.session
        let rolling = try #require(CoachingReference.fastestRolling.resolve(in: session, stepMeters: 2))
        for distance in stride(from: 0.0, to: rolling.lengthMeters, by: 97) {
            let piece = try #require(rolling.piece(at: distance))
            let lap = try #require(session.laps.first { $0.number == piece.lapNumber })
            let time = rolling.sessionTime(atDistance: distance)
            #expect(time >= lap.start - 0.5 && time <= (lap.end ?? .infinity) + 0.5)
        }
    }

    @Test func spansRoundTrip() throws {
        let span = TrafficSpan(start: 12.5, end: 30, kind: .flag)
        let decoded = try JSONDecoder().decode(TrafficSpan.self, from: try JSONEncoder().encode(span))
        #expect(decoded == span)
    }
}
