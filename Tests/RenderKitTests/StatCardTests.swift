import CoreGraphics
import CoreVideo
import Foundation
import Testing

@testable import ProjectModel
@testable import RenderKit
@testable import TelemetryKit

@Suite("Stat card (#151)", .gpu)
struct StatCardTests {
    func card(
        _ params: StatCardParams, session: TelemetrySession = SyntheticSession.session, unit: SpeedDisplayUnit = .kph
    ) -> StatCardRenderer {
        let context = ObjectContext(
            objectID: DisplayObjectID(UUID(uuidString: "00000000-0000-0000-0000-000000000151") ?? UUID()),
            frame: UnitRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9), opacity: 1,
            sampler: TelemetrySampler(session: session), sync: .identity, cache: RenderCache(),
            speedUnit: unit)
        return StatCardRenderer(context: context, params: params)
    }

    @Test func theSessionCardListsTheHeadlineNumbers() {
        let rows = card(StatCardParams()).rows(at: 5)
        #expect(rows.map(\.label) == ["Best lap (0)", "Top speed", "Laps"])  // no sectors, no optimal lap
        #expect(rows[0].value == TimeParsing.lapTimeString(4))
        #expect(rows[1].value == "126 kph")  // 35 m/s
        #expect(rows[2].value == "2")
    }

    @Test func theLapCardFollowsThePlayhead() {
        let lapCard = card(StatCardParams(scope: .lapAtPlayhead))
        let lap1 = lapCard.rows(at: 6)
        #expect(lap1.map(\.label) == ["Lap 1", "To best", "Top speed"])
        #expect(lap1[1].value == "+0.50 s")
        #expect(lap1[2].value == "113 kph")  // 31.25 m/s at the end of lap 1
        #expect(lapCard.rows(at: 2)[1].value == "Best lap")
        // The partial lap has no time of its own.
        #expect(lapCard.rows(at: 9.5).first?.value == "—")
    }

    @Test func rowsCanBeTurnedOff() {
        let rows = card(StatCardParams(showBestLap: false, showLapCount: false)).rows(at: 5)
        #expect(rows.map(\.label) == ["Top speed"])
    }

    @Test func theTitleTakesTheProjectsDetails() {
        let kind = DisplayObjectKind.statCard(StatCardParams())
        let filled = kind.filling(ProjectDetails(track: "Sonoma", date: "2026-08-23"))
        guard case .statCard(let params) = filled else { return #expect(Bool(false)) }
        #expect(params.title.hasPrefix("Sonoma · "))
    }

    @Test func aCardLooksTheSameEveryTime() throws {
        let renderer = card(StatCardParams(title: "Sonoma · 23 Aug 2026"))
        let plan = RenderPlan(outputWidth: 400, outputHeight: 400, frameRate: 30, videoLayers: [], overlays: [renderer])
        let frame = try FrameCompositor(plan: plan).renderFrame(sources: [:], time: 5)
        try GoldenImage.assertMatches(frame, named: "stat-card-session")
    }

    // MARK: - Performance runs (#553)

    /// The synthetic session with two launches, the second quicker, and a stop after each.
    static var measured: TelemetrySession {
        var session = SyntheticSession.session
        var first = PerformanceRuns.Attempt(start: 1, end: 3, sampleHertz: 10)
        first.speedTimes = [.zeroToSixtyMph: 6.2, .zeroToHundredKmh: 6.5]
        first.distanceTimes = [.quarterMile: 14.1]
        first.trapSpeeds = [.quarterMile: 45]
        var second = PerformanceRuns.Attempt(start: 5, end: 7, sampleHertz: 10)
        second.speedTimes = [.zeroToSixtyMph: 5.36, .zeroToHundredKmh: 5.56]
        session.performance = PerformanceRuns.Result(
            attempts: [first, second],
            stops: [
                PerformanceRuns.Stop(from: .sixtyMph, start: 3, end: 4, metres: 36),
                PerformanceRuns.Stop(from: .hundredKmh, start: 7.5, end: 8.5, metres: 38.6),
            ])
        return session
    }

    static let performanceRows = StatCardParams(
        showBestLap: false, showTopSpeed: false, showOptimalLap: false, showLapCount: false, showLaunch: true,
        showQuarterMile: true, showStop: true)

    @Test func theSessionCardShowsTheBestLaunchQuarterMileAndStop() {
        let mph = card(Self.performanceRows, session: Self.measured, unit: .mph).rows(at: 5)
        #expect(mph.map(\.label) == ["0–60 mph", "¼ mile", "60–0 mph"])
        #expect(mph.map(\.value) == ["5.36 s", "14.10 s @ 101 mph", "118 ft"])
        let kph = card(Self.performanceRows, session: Self.measured).rows(at: 5)
        #expect(kph.map(\.label) == ["0–100 km/h", "402 m", "100–0 km/h"])
        #expect(kph.map(\.value) == ["5.56 s", "14.10 s @ 162 km/h", "38.6 m"])
    }

    @Test func theLapCardShowsTheAttemptAtThePlayhead() {
        var params = Self.performanceRows
        params.scope = .lapAtPlayhead
        let rows = card(params, session: Self.measured, unit: .mph).rows(at: 2)
        #expect(rows.suffix(3).map(\.value) == ["6.20 s", "14.10 s @ 101 mph", "118 ft"])
        // The second attempt never ran a quarter mile.
        #expect(card(params, session: Self.measured, unit: .mph).rows(at: 6).suffix(3).map(\.value)[1] == "—")
    }

    @Test func noRowsWithoutPerformanceRunsOrBeforeTheyWereAsked() throws {
        #expect(card(Self.performanceRows).rows(at: 5).isEmpty, "not measured: nothing to show")
        #expect(
            StatCardRenderer(context: card(StatCardParams()).context, params: Self.performanceRows).plannedRows == 3)
        // A card saved before has none of the three.
        let old = try JSONDecoder().decode(StatCardParams.self, from: Data(#"{"title":"Sonoma"}"#.utf8))
        #expect(!old.showLaunch && !old.showQuarterMile && !old.showStop)
        var fresh = old
        fresh.title = StatCardParams().title
        #expect(fresh == StatCardParams(), "and every other setting as a new card has it")
    }
}
