import Foundation
import Importers
import TelemetryKit
import Testing

@testable import ProjectModel

@Suite("Coaching sheet (#331)")
struct CoachingSheetTests {
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/coaching-laps.csv")

    func sheet(plan: NextSessionPlan? = nil) throws -> CoachingSheet {
        let session = try RaceRenderCSVImporter().importSession(at: Self.fixture, options: SessionBuilder.Options())
        let slow = session.laps[1]
        let analysis = try #require(CoachingAnalysis.analyse(lap: slow, reference: .sessionBest, in: session))
        return CoachingSheet(
            analysis: analysis, lapNumber: slow.number, units: .metric, title: "Stadium", subtitle: "1 May · Me",
            plan: plan, warnings: ["A note."])
    }

    @Test func theMarkdownHasTheNotesThePlanAndEveryCorner() throws {
        let plan = NextSessionPlan(experiments: [PlannedExperiment(cornerLabel: "1", text: "Brake later.")])
        let sheet = try sheet(plan: plan)
        let markdown = sheet.markdown
        #expect(markdown.hasPrefix("# Stadium — Lap 2\n*1 May · Me*\n"))
        #expect(markdown.contains("**Lap 2 "))
        #expect(markdown.contains("## Next session, try…\n\n1. **Turn 1** — Brake later."))
        #expect(markdown.contains("## Where the time went\n\n1. **Turn "))
        #expect(markdown.contains("   - *Try:* "))
        #expect(markdown.contains("| Turn | Lost | Phase | Brake | Min speed | Where | Exit | Throttle | Consistent |"))
        #expect(markdown.contains("\n| 1 | +"))
        #expect(markdown.contains("\n| 2 | "))
        #expect(markdown.hasSuffix("- A note.\n"))
        #expect(sheet.fileStem == "Stadium – Lap 2 coaching sheet")
        // Without a plan there is no plan section.
        #expect(!(try self.sheet().markdown.contains("Next session")))
    }

    @Test func theMapFitsAUnitSquareWithACornerMarkPerCorner() throws {
        let sheet = try sheet()
        #expect(sheet.outline.count > 100)
        #expect(sheet.outline.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        #expect(sheet.corners.map(\.label) == ["1", "2"])
        #expect(sheet.corners.allSatisfy { (0...1).contains($0.point.x) && (0...1).contains($0.point.y) })
        #expect(sheet.rows.count == 2)
        #expect(sheet.opportunities.count == 2)
    }
}
