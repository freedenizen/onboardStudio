import Foundation
import Testing

@testable import TelemetryKit

@Suite("Coaching analysis")
struct CoachingAnalysisTests {
    /// Fast, slow, fast, fast: lap 2 is the one to coach, the best lap is lap 1.
    static let session: TelemetrySession = {
        var session = CoachingFixture.session(
            drivings: [CoachingFixture.fast, CoachingFixture.slow, CoachingFixture.fast, CoachingFixture.fast])
        session.cornerLabels = ["1", "2"]
        return session
    }()

    @Test func aSlowLapAgainstTheBestHasRankedOpportunitiesWithNotes() throws {
        let session = Self.session
        let analysis = try #require(
            CoachingAnalysis.analyse(lap: session.laps[1], reference: .sessionBest, in: session))
        // Laps 1, 3 and 4 are identical to floating point; any of them is the best.
        #expect(["Lap 1", "Lap 3", "Lap 4"].contains(analysis.reference.label))
        #expect(analysis.referencePhrase == "your best lap")
        #expect(analysis.delta.alignment == .distance)
        #expect(analysis.corners.count == 2)
        #expect(analysis.totalLoss > 1)
        // Both corners lost time; the bigger loss ranks first.
        #expect(analysis.opportunities.count == 2)
        #expect(analysis.opportunities.map(\.rank) == [1, 2])
        #expect(analysis.opportunities[0].timeLost >= analysis.opportunities[1].timeLost)
        #expect(analysis.top.count == 2)
        for opportunity in analysis.opportunities {
            let note = opportunity.note
            #expect(note.headline.hasPrefix("Turn \(opportunity.corner.label): "))
            #expect(note.headline.contains("lost on"))
            // The slow lap braked 47 m earlier, over-slowed by 2 m/s and found its minimum 20 m late.
            #expect(note.evidence.contains { $0.hasPrefix("Braked ") && $0.contains("earlier than your best lap") })
            #expect(note.evidence.contains { $0.hasPrefix("Minimum speed ") && $0.contains("lower") })
            #expect(note.evidence.contains("Pedals read from the speed trace"))
            #expect(note.suggestion.hasPrefix("This corner varies lap to lap (brake point spread "))
            #expect(note.suggestion.contains("repeat your best lap's brake point first, then try "))
            #expect(opportunity.kind != .line)
        }
        // Three fast laps and one slow: brake points spread well past 10 m, so the corner is
        // inconsistent and consistency comes first in the suggestion. That is said in the
        // suggestion, not in the headline.
        let consistency = try #require(analysis.consistency)
        #expect(consistency.lapCount == 4)
        #expect(consistency.corners.count == 2)
        #expect(consistency.corners.allSatisfy { !$0.isConsistent })
        #expect((consistency.corners[0].brakePointSpread ?? 0) > 10)
        #expect(analysis.warnings.contains(.pedalsFromSpeedTrace))
        #expect(!analysis.warnings.contains(.approximateAlignment))
        #expect(!analysis.warnings.contains(.tooFewLapsForConsistency))
    }

    @Test func notesAreWrittenInTheUnitsAsked() throws {
        let session = Self.session
        let metric = try #require(
            CoachingAnalysis.analyse(lap: session.laps[1], reference: .sessionBest, in: session))
        let imperial = try #require(
            CoachingAnalysis.analyse(lap: session.laps[1], reference: .sessionBest, in: session, units: .imperial))
        let metricBrake = try #require(metric.opportunities[0].note.evidence.first { $0.hasPrefix("Braked ") })
        let imperialBrake = try #require(imperial.opportunities[0].note.evidence.first { $0.hasPrefix("Braked ") })
        #expect(metricBrake.contains(" m earlier"))
        #expect(imperialBrake.contains(" ft earlier"))
        let metricSpeed = try #require(
            metric.opportunities[0].note.evidence.first { $0.hasPrefix("Minimum speed ") })
        let imperialSpeed = try #require(
            imperial.opportunities[0].note.evidence.first { $0.hasPrefix("Minimum speed ") })
        #expect(metricSpeed.contains("km/h"))
        #expect(imperialSpeed.contains("mph"))
        let format = CoachingNotes.Formatter(units: .imperial)
        #expect(format.metres(30.48) == "100 ft")
        #expect(format.speed(44.704) == "100 mph")
        #expect(CoachingNotes.Formatter(units: .metric).seconds(0.314) == "0.31 s")
    }

    @Test func theSameNoteComesOutEveryTime() throws {
        let session = Self.session
        let first = try #require(
            CoachingAnalysis.analyse(lap: session.laps[1], reference: .sessionBest, in: session))
        let second = try #require(
            CoachingAnalysis.analyse(lap: session.laps[1], reference: .sessionBest, in: session))
        #expect(first.opportunities == second.opportunities)
    }

    @Test func aLapAgainstItselfHasNothingToSay() throws {
        let session = Self.session
        let analysis = try #require(CoachingAnalysis.analyse(lap: session.laps[0], reference: .lap(1), in: session))
        #expect(analysis.opportunities.isEmpty)
        #expect(abs(analysis.totalLoss) < 1e-9)
        #expect(analysis.referencePhrase == "lap 1")
    }

    @Test func spliedReferencesWorkAndWarnAboutSeamsInCorners() throws {
        let session = Self.session
        let rolling = try #require(
            CoachingAnalysis.analyse(lap: session.laps[1], reference: .fastestRolling, in: session))
        #expect(rolling.referencePhrase == "the rolling lap")
        #expect(rolling.corners.count == 2)
        // Equal-distance quarters put a seam at each bend's apex (294 m and 882 m).
        var sectored = session
        sectored.sectors = Sectors.analyse(mode: .equalDistance(count: 4), session: session)
        let optimal = try #require(
            CoachingAnalysis.analyse(lap: session.laps[1], reference: .compositeOptimal, in: sectored))
        #expect(optimal.reference.isSpliced)
        #expect(optimal.corners.count == 2)
        #expect(optimal.warnings.contains(.seamInCorner(labels: ["1", "2"])))
        // Corner-aware sectors keep the seam on the back straight, so no warning. (Two corners
        // give one straight to put a boundary on, hence two sectors.)
        var aware = session
        aware.sectors = Sectors.analyse(mode: .cornerAware(count: 2), session: session)
        let clean = try #require(
            CoachingAnalysis.analyse(lap: session.laps[1], reference: .compositeOptimal, in: aware))
        let seamWarnings = clean.warnings.filter {
            if case .seamInCorner = $0 { return true } else { return false }
        }
        #expect(seamWarnings.isEmpty)
    }

    @Test func anotherSessionsLapIsAlignedByPosition() throws {
        let session = Self.session
        // The same circuit 3 m to the east, driven slow: a different session, a different line.
        let other = LapAlignmentTests.shifted(CoachingFixture.session(drivings: [CoachingFixture.slow]), east: 3)
        let lap = try #require(LapProfile(lap: other.laps[0], in: other))
        let reference = try #require(LapProfile(lap: session.laps[0], in: session))
        let analysis = try #require(
            CoachingAnalysis.analyse(
                lap: lap, in: other, reference: reference, referencePhrase: "Alex (Sunday)", sameSession: false))
        #expect(analysis.delta.alignment == .byPosition)
        #expect(analysis.corners.count == 2)
        #expect(analysis.consistency == nil)
        #expect(!analysis.warnings.contains(.tooFewLapsForConsistency))
        let note = try #require(analysis.opportunities.first?.note)
        #expect(note.evidence.contains { $0.contains("than Alex (Sunday)") })
        // The brake point is read on the other lap at the matched place, so the reading is the
        // slow lap's own, not shifted by the alignment.
        let brake = try #require(analysis.corners[0].lap.brakePointMeters)
        #expect(abs(brake - CoachingFixture.slow.brakePointBeforeApex) < 10, "\(brake)")
    }

    @Test func aCompromiseTheNextCornerWinsBackIsNotAnOpportunity() throws {
        let session = Self.session
        let analysis = try #require(
            CoachingAnalysis.analyse(lap: session.laps[1], reference: .sessionBest, in: session))
        let first = analysis.corners[0]
        let second = analysis.corners[1]
        // Hand the second corner a gain bigger than the first's loss.
        let paidBack = CornerComparison(
            index: second.index, label: second.label, lap: second.lap, reference: second.reference,
            timeLost: -(first.timeLost + 1), phaseLoss: [.exit: -(first.timeLost + 1)])
        let ranked = Coaching.rank(
            [first, paidBack], consistency: nil, referencePhrase: "your best lap", units: .metric,
            options: CoachingOptions())
        #expect(ranked.isEmpty)
        // Below the minimum loss, nothing is an opportunity either.
        var strict = CoachingOptions()
        strict.minimumLossSeconds = 1000
        let none = Coaching.rank(
            analysis.corners, consistency: nil, referencePhrase: "x", units: .metric, options: strict)
        #expect(none.isEmpty)
    }

    @Test func consistencyNeedsThreeLaps() {
        let two = CoachingFixture.session(drivings: [CoachingFixture.fast, CoachingFixture.slow])
        let corners = CornerDetector.corners(of: two.laps[0], in: two)
        #expect(ConsistencyStats.measure(in: two, corners: corners) == nil)
        let analysis = CoachingAnalysis.analyse(lap: two.laps[1], reference: .sessionBest, in: two)
        #expect(analysis?.consistency == nil)
        #expect(analysis?.warnings.contains(.tooFewLapsForConsistency) == true)
        // Four identical laps are perfectly consistent.
        let steady = CoachingFixture.session(drivings: Array(repeating: CoachingFixture.fast, count: 4))
        let steadyCorners = CornerDetector.corners(of: steady.laps[0], in: steady)
        let stats = ConsistencyStats.measure(in: steady, corners: steadyCorners)
        #expect(stats?.corners.allSatisfy(\.isConsistent) == true)
        #expect((stats?.lapTimeSpread ?? 1) < 1e-6)
        let deviation = ConsistencyStats.deviation([2, 4, 4, 4, 5, 5, 7, 9])
        #expect(deviation > 2.13 && deviation < 2.14)
    }
}
