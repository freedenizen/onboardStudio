import Foundation
import Importers
import TelemetryKit
import Testing

@testable import ProjectModel

@Suite("Next-session plan (#330)")
struct NextSessionPlanTests {
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/coaching-laps.csv")

    @Test func thePlanIsWrittenFromTheOpportunitiesInTheirOwnWords() throws {
        let session = try RaceRenderCSVImporter().importSession(at: Self.fixture, options: SessionBuilder.Options())
        let slow = session.laps[1]
        let analysis = try #require(CoachingAnalysis.analyse(lap: slow, reference: .sessionBest, in: session))
        let plan = NextSessionPlan.suggested(from: analysis, lapNumber: slow.number)
        #expect(plan.experiments.count == min(analysis.opportunities.count, 3))
        #expect(plan.experiments.count == 2, "the slow lap loses time in both corners")
        #expect(plan.experiments.map(\.cornerLabel) == analysis.opportunities.prefix(2).map(\.corner.label))
        #expect(plan.experiments.map(\.text) == analysis.opportunities.prefix(2).map(\.note.suggestion))
        #expect(plan.fromLap == slow.number)
        #expect(plan.referencePhrase == "your best lap")
        #expect(plan.experiments[0].title == "Turn \(plan.experiments[0].cornerLabel)")
        #expect(plan.summary.hasPrefix("Turn \(plan.experiments[0].cornerLabel): "))
        #expect(NextSessionPlan.suggested(from: analysis, lapNumber: 2, count: 1).experiments.count == 1)
    }

    /// #333: the option the window offers, on two laps of one session.
    @Test func twoLapsOfOneSessionCanBeLinedUpByPosition() throws {
        let session = try RaceRenderCSVImporter().importSession(at: Self.fixture, options: SessionBuilder.Options())
        let slow = session.laps[1]
        var options = CoachingOptions()
        options.alignment = .byPosition
        let byPosition = try #require(
            CoachingAnalysis.analyse(lap: slow, reference: .sessionBest, in: session, options: options))
        let byDistance = try #require(CoachingAnalysis.analyse(lap: slow, reference: .sessionBest, in: session))
        #expect(byPosition.delta.alignment == .byPosition)
        #expect(byDistance.delta.alignment == .distance)
        #expect(byPosition.alignmentLine.hasPrefix("Aligned by position"))
        // The same line driven twice reads the same either way, to within the matching step.
        #expect(abs(byPosition.totalLoss - byDistance.totalLoss) < 0.3)
        #expect(byPosition.corners.count == byDistance.corners.count)
    }

    @Test func thePlanRoundTripsInTheProjectAndIsAbsentInOlderFiles() throws {
        let plan = NextSessionPlan(
            experiments: [
                PlannedExperiment(cornerLabel: "4", text: "Brake at the 2 board."),
                PlannedExperiment(cornerLabel: "", text: "Breathe."),
            ],
            fromLap: 5, referencePhrase: "your best lap", made: Date(timeIntervalSince1970: 1_700_000_000))
        var project = Project()
        project.plan = plan
        let data = try JSONEncoder().encode(project)
        let back = try JSONDecoder().decode(Project.self, from: data)
        #expect(back.plan == plan)
        #expect(back.plan?.experiments[1].title == "Anywhere")
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["plan"] = nil
        let older = try JSONDecoder().decode(Project.self, from: try JSONSerialization.data(withJSONObject: json))
        #expect(older.plan == nil)
    }

    @Test func theTrackDefinitionCarriesThePlanAndOlderOnesHaveNone() throws {
        let plan = NextSessionPlan(experiments: [PlannedExperiment(cornerLabel: "7", text: "Later apex.")], fromLap: 3)
        let definition = TrackDefinition(circuitID: "Q1", name: "Stadium", latitude: 1, longitude: 2, plan: plan)
        let data = try JSONEncoder().encode(definition)
        let back = try JSONDecoder().decode(TrackDefinition.self, from: data)
        #expect(back.plan == plan)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["plan"] = nil
        let older = try JSONDecoder().decode(
            TrackDefinition.self, from: try JSONSerialization.data(withJSONObject: json))
        #expect(older.plan == nil)
        #expect(older.name == "Stadium")
        // The library writes and reads it back.
        let folder = FileManager.default.temporaryDirectory.appending(path: "plan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = TrackLibrary(directory: folder)
        try library.save(definition)
        #expect(library.definition(id: "Q1")?.plan == plan)
    }
}
