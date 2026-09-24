import CoreGraphics
import CoreVideo
import Foundation
import Testing

@testable import ProjectModel
@testable import RenderKit
@testable import TelemetryKit

@Suite("Stat card (#151)")
struct StatCardTests {
    func card(_ params: StatCardParams) -> StatCardRenderer {
        let context = ObjectContext(
            objectID: DisplayObjectID(UUID(uuidString: "00000000-0000-0000-0000-000000000151") ?? UUID()),
            frame: UnitRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9), opacity: 1,
            sampler: TelemetrySampler(session: SyntheticSession.session), sync: .identity, cache: RenderCache(),
            speedUnit: .kph)
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
}
