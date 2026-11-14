import Foundation
import Testing

@testable import TelemetryKit

/// Traffic suggestions from the telemetry (#572): a lap that lifts where the others are flat out,
/// or takes a corner far slower than usual, is pointed at, and nothing else changes.
@Suite("Traffic suggestions")
struct TrafficSuggestionsTests {
    static let fast = CoachingFixture.fast
    /// Fast, fast, slow, fast: lap 3 brakes about 45 m early into both bends and over-slows, as
    /// a driver caught behind a slower car would.
    static func session(pedals: Bool) -> TelemetrySession {
        CoachingFixture.session(drivings: [fast, fast, CoachingFixture.slow, fast], pedals: pedals)
    }

    static func corners(of session: TelemetrySession) throws -> [Corner] {
        CornerDetector.corners(of: try #require(LapProfile(lap: session.laps[0], in: session)))
    }

    static func find(in session: TelemetrySession) throws -> [TrafficSuggestion] {
        TrafficSuggestions.find(in: session, corners: try corners(of: session))
    }

    static var suggesting: CoachingOptions {
        var options = CoachingOptions()
        options.suggestsTraffic = true
        return options
    }

    @Test(arguments: [true, false])
    func theSlowLapIsPointedAtInBothCornersAndNoOtherLapIs(pedals: Bool) throws {
        let session = Self.session(pedals: pedals)
        let suggestions = try Self.find(in: session)
        #expect(suggestions.map(\.lapNumber) == [3, 3])
        #expect(suggestions.map(\.corner) == [0, 1])
        #expect(suggestions.map(\.label) == ["1", "2"])
        for suggestion in suggestions {
            let lift = suggestion.evidence.compactMap { evidence -> (Double, Bool)? in
                if case .lift(let meters, let fromThrottle) = evidence { (meters, fromThrottle) } else { nil }
            }
            #expect(lift.count == 1)
            #expect(lift.first?.1 == pedals)
            // The braking began about 45 m early: the throttle shows most of it, the smoothed speed
            // trace less, and both more than the 20 m a lift must last.
            #expect((lift.first?.0 ?? 0) > (pedals ? 30 : 20))
            #expect(suggestion.sentence(units: .metric).hasPrefix(pedals ? "You lifted for" : "You slowed for"))
            #expect(suggestion.evidence.contains { if case .slow = $0 { true } else { false } })
            // The stretch is on lap 3.
            let lap = session.laps[2]
            #expect(suggestion.window.start >= lap.start && suggestion.window.end <= (lap.end ?? .infinity))
        }
    }

    @Test func identicalLapsSuggestNothing() throws {
        let session = CoachingFixture.session(drivings: [Self.fast, Self.fast, Self.fast, Self.fast], pedals: true)
        #expect(try Self.find(in: session).isEmpty)
    }

    @Test func tooFewLapsSayNothingAboutWhatIsUsual() throws {
        let session = CoachingFixture.session(drivings: [Self.fast, CoachingFixture.slow], pedals: true)
        #expect(try Self.find(in: session).isEmpty)
    }

    @Test func aCoolDownLapIsNeitherReadNorComparedWith() throws {
        var crawl = CoachingFixture.slow
        crawl.topSpeed = 20
        crawl.minimumSpeed = 10
        let session = CoachingFixture.session(drivings: [Self.fast, Self.fast, crawl, Self.fast], pedals: true)
        let durations = session.laps.compactMap(\.duration)
        #expect(durations[2] > (durations.min() ?? 0) * 1.5)
        #expect(try Self.find(in: session).isEmpty)
    }

    @Test func aMarkOrADismissalHidesTheSuggestion() throws {
        let session = Self.session(pedals: true)
        let suggestions = try Self.find(in: session)
        let first = try #require(suggestions.first)
        var marked = session
        marked.traffic = [TrafficSpan(start: first.window.start, end: first.window.start + first.window.duration / 2)]
        #expect(try Self.find(in: marked).map(\.window) == [suggestions[1].window])
        // A mark that only meets it at an end, as the corner before's does, has not answered it.
        var met = session
        met.traffic = [TrafficSpan(start: first.window.start - 10, end: first.window.start)]
        #expect(try Self.find(in: met).count == 2)
        var dismissed = session
        dismissed.dismissedTraffic = [first.window]
        #expect(try Self.find(in: dismissed).map(\.window) == [suggestions[1].window])
        // A dismissal that only grazes a suggestion leaves it offered.
        var grazed = session
        grazed.dismissedTraffic = [LapProfile.Window(start: first.window.end - 0.2, end: first.window.end + 5)]
        #expect(try Self.find(in: grazed).count == 2)
    }

    @Test func theSuggestionsHangOnTheLapsCornersAndChangeNothingElse() throws {
        let session = Self.session(pedals: true)
        let plain = try #require(
            CoachingAnalysis.analyse(lap: session.laps[2], reference: .sessionBest, in: session))
        #expect(plain.suggestions.isEmpty)
        #expect(plain.corners.allSatisfy { $0.suggestion == nil })
        let read = try #require(
            CoachingAnalysis.analyse(
                lap: session.laps[2], reference: .sessionBest, in: session, options: Self.suggesting))
        #expect(read.suggestions.count == 2)
        #expect(read.corners.map { $0.suggestion?.lapNumber } == [3, 3])
        #expect(read.rows(units: .metric).map { $0.suggestion != nil } == [true, true])
        // Still coached, word for word.
        #expect(read.opportunities.map(\.note) == plain.opportunities.map(\.note))
        #expect(read.headline(lapNumber: 3, units: .metric) == plain.headline(lapNumber: 3, units: .metric))
        #expect(read.trafficLoss == 0)
        // A fast lap's corners carry none.
        let fastLap = try #require(
            CoachingAnalysis.analyse(
                lap: session.laps[3], reference: .sessionBest, in: session, options: Self.suggesting))
        #expect(fastLap.corners.allSatisfy { $0.suggestion == nil })
    }

    @Test func aMarkedCornerTakesNoSuggestion() throws {
        let session = Self.session(pedals: true)
        let read = try #require(
            CoachingAnalysis.analyse(
                lap: session.laps[2], reference: .sessionBest, in: session, options: Self.suggesting))
        let times = read.sessionTimes(of: read.corners[0])
        var marked = session
        marked.traffic = [TrafficSpan(start: times.lowerBound, end: times.upperBound)]
        let again = try #require(
            CoachingAnalysis.analyse(lap: marked.laps[2], reference: .sessionBest, in: marked, options: Self.suggesting)
        )
        #expect(again.corners[0].traffic != nil)
        #expect(again.corners[0].suggestion == nil)
        #expect(again.corners[1].suggestion != nil)
    }

    @Test func theSentenceSaysWhatWasSeen() {
        let window = LapProfile.Window(start: 10, end: 14)
        let both = TrafficSuggestion(
            lapNumber: 3, corner: 2, label: "3", window: window,
            evidence: [.lift(meters: 40, fromThrottle: true), .slow(seconds: 1.2)])
        #expect(
            both.sentence(units: .metric)
                == "You lifted for 40 m where most of your other laps were flat out and Turn 3 took 1.20 s longer than "
                + "it usually does")
        let slowed = TrafficSuggestion(
            lapNumber: 3, corner: 2, label: "3", window: window, evidence: [.lift(meters: 25, fromThrottle: false)])
        #expect(slowed.sentence(units: .metric) == "You slowed for 25 m where most of your other laps did not")
    }

    @Test func runsBridgeShortGaps() {
        let flags = [false, true, true, false, true, false, false, false, true]
        #expect(TrafficSuggestions.runs(of: flags, bridging: 1) == [1...4, 8...8])
        #expect(TrafficSuggestions.runs(of: flags, bridging: 0) == [1...2, 4...4, 8...8])
    }

    @Test func eachCornerRunsFromItsBrakePointToTheNextOnes() throws {
        let session = Self.session(pedals: true)
        let corners = try Self.corners(of: session)
        let quickest = try #require(LapProfile(lap: session.laps[0], in: session))
        let bounds = TrafficSuggestions.boundaries(of: corners, on: quickest, options: CoachingOptions())
        #expect(bounds.count == corners.count + 1)
        #expect(bounds.first == 0 && bounds.last == 1)
        let second = try #require(
            CornerMetrics.measure(corners: corners, of: quickest).first { $0.index == 1 })
        #expect(abs(bounds[1] * quickest.lengthMeters - second.phaseStart) < 1e-6)
    }

    @Test func suggestionsRoundTrip() throws {
        let suggestion = TrafficSuggestion(
            lapNumber: 2, corner: 0, label: "1", window: .init(start: 10, end: 14),
            evidence: [.lift(meters: 30, fromThrottle: true), .slow(seconds: 0.5)])
        let decoded = try JSONDecoder().decode(
            TrafficSuggestion.self, from: try JSONEncoder().encode(suggestion))
        #expect(decoded == suggestion)
    }
}
