import Foundation
import Testing

@testable import TelemetryKit

/// #555: Coaching says a distance only as closely as the session's positions can place it, and
/// reads no brake point across a dropout.
@Suite("Coaching to the GPS's precision (#555)")
struct CoachingGPSPrecisionTests {
    /// `CoachingAnalysisTests.session` — fast, slow, fast, fast — with what its GPS was like.
    static func session(precision: Double = 12, dropouts: [GPSQuality.Gap] = [], legacy: Bool = false)
        -> TelemetrySession
    {
        var session = CoachingAnalysisTests.session
        session.gpsQuality = GPSQuality(rateHertz: 1, dropouts: dropouts, precisionMeters: precision)
        session.legacyExactDistances = legacy
        return session
    }

    static func analysis(_ session: TelemetrySession, units: CoachingUnits = .metric) throws -> CoachingAnalysis {
        try #require(CoachingAnalysis.analyse(lap: session.laps[1], reference: .sessionBest, in: session, units: units))
    }

    @Test func coarseDataSaysDistancesRoundedAndWhy() throws {
        let analysis = try Self.analysis(Self.session())
        #expect(analysis.options.distanceStepMeters == 15)
        let evidence = analysis.opportunities.flatMap(\.note.evidence)
        let brake = try #require(evidence.first { $0.hasPrefix("Braked ") })
        #expect(brake.hasPrefix("Braked ≈ "), "\(brake)")
        let metres = try #require(Int(brake.split(separator: " ")[2]))
        #expect(metres % 15 == 0, "to the nearest 15 m: \(brake)")
        #expect(evidence.contains("Distances to the nearest 15 m, as close as this GPS allows"))
    }

    @Test func goodDataAndProjectsSavedBeforeSayThemToTheMetre() throws {
        let good = try Self.analysis(Self.session(precision: 0.5))
        let legacy = try Self.analysis(Self.session(legacy: true))
        let none = try Self.analysis(CoachingAnalysisTests.session)
        #expect(good.options.distanceStepMeters == 1 && legacy.options.distanceStepMeters == 1)
        #expect(good.opportunities == none.opportunities)
        #expect(legacy.opportunities == none.opportunities, "a saved project's callouts keep their words")
        #expect(!none.opportunities.flatMap(\.note.evidence).contains { $0.contains("≈") })
    }

    @Test func noDifferenceFinerThanTheDataIsJudged() throws {
        // At 1 Hz on a fast car the brake points are no closer than 100 m: none is earlier or later.
        let analysis = try Self.analysis(Self.session(precision: 90))
        #expect(!analysis.opportunities.contains { $0.kind == .brakedEarly || $0.kind == .brakedLate })
        #expect(!analysis.opportunities.flatMap(\.note.evidence).contains { $0.hasPrefix("Braked ") })
    }

    @Test func aDropoutThroughACornerLeavesItsBrakePointUnread() throws {
        let plain = try Self.analysis(CoachingAnalysisTests.session)
        let corner = try #require(plain.corners.first)
        let times = plain.sessionTimes(of: corner)
        let gap = GPSQuality.Gap(start: times.lowerBound + 0.2, end: times.lowerBound + 1)
        let analysis = try Self.analysis(Self.session(precision: 0.5, dropouts: [gap]))
        #expect(analysis.corners[0].gpsGap)
        #expect(analysis.corners.dropFirst().allSatisfy { !$0.gpsGap }, "only the corner it was in")
        let note = try #require(analysis.opportunities.first { $0.corner.index == corner.index }?.note)
        #expect(note.evidence.first == "No brake point: the GPS dropped out through this corner")
        #expect(!note.evidence.contains { $0.hasPrefix("Braked ") || $0.hasPrefix("Did not brake") })
        let kind = try #require(analysis.opportunities.first { $0.corner.index == corner.index }?.kind)
        #expect(kind != .brakedEarly && kind != .brakedLate)
        // A project saved before reads it as it did.
        #expect(!(try Self.analysis(Self.session(precision: 0.5, dropouts: [gap], legacy: true)).corners[0].gpsGap))
    }

    @Test func roundingSnapsToANumberADriverSays() {
        let metric = CoachingNotes.Formatter(units: .metric, stepMeters: 15)
        #expect(metric.metres(37) == "≈ 30 m")
        #expect(metric.metres(3) == "≈ 15 m", "never nought")
        #expect(metric.step == "15 m")
        let imperial = CoachingNotes.Formatter(units: .imperial, stepMeters: 15)
        #expect(imperial.step == "50 ft")
        #expect(imperial.metres(37) == "≈ 100 ft")
        #expect(CoachingNotes.Formatter(units: .metric).metres(37) == "37 m")
    }
}
