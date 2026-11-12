import Foundation
import Importers
import TelemetryKit
import Testing

@testable import ProjectModel

@Suite("Guided coaching (#458)")
struct CoachingWalkthroughTests {
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/coaching-laps.csv")

    static func analysis() throws -> CoachingAnalysis {
        let session = try RaceRenderCSVImporter().importSession(at: fixture, options: SessionBuilder.Options())
        return try #require(CoachingAnalysis.analyse(lap: session.laps[1], reference: .sessionBest, in: session))
    }

    @Test func theLapThenItsBiggestLossesThenThePlan() throws {
        let analysis = try Self.analysis()
        let walkthrough = CoachingWalkthrough(analysis: analysis)
        // The corners the cards show, biggest loss first.
        #expect(walkthrough.corners == analysis.top.map(\.corner.index))
        #expect(!walkthrough.corners.isEmpty)
        #expect(walkthrough.corners.count <= 3)
        #expect(walkthrough.steps.first == .lap)
        #expect(walkthrough.steps.last == .plan)
        #expect(walkthrough.steps.count == walkthrough.corners.count + 2)
    }

    @Test func nextAndBackWalkTheStepsAndStopAtTheEnds() {
        let walkthrough = CoachingWalkthrough(corners: [4, 7, 2])
        #expect(walkthrough.next(after: .lap) == .corner(4))
        #expect(walkthrough.next(after: .corner(4)) == .corner(7))
        #expect(walkthrough.next(after: .corner(2)) == .plan)
        #expect(walkthrough.next(after: .plan) == nil)
        #expect(walkthrough.previous(before: .plan) == .corner(2))
        #expect(walkthrough.previous(before: .corner(4)) == .lap)
        #expect(walkthrough.previous(before: .lap) == nil)
        // A step not in this walkthrough — a corner from another lap's reading — goes nowhere.
        #expect(walkthrough.next(after: .corner(9)) == nil)
    }

    @Test func aCornerSaysWhichOfHowManyItIs() {
        let walkthrough = CoachingWalkthrough(corners: [4, 7, 2])
        #expect(walkthrough.position(of: .corner(7))?.number == 2)
        #expect(walkthrough.position(of: .corner(7))?.count == 3)
        #expect(walkthrough.position(of: .lap) == nil)
        #expect(walkthrough.position(of: .plan) == nil)
        #expect(walkthrough.position(of: .corner(9)) == nil)
        // A lap that lost nothing is the lap and the plan.
        #expect(CoachingWalkthrough(corners: []).steps == [.lap, .plan])
    }

    @Test func thePlanIsWhatTheDriverChoseInTheAnalysissWords() throws {
        let analysis = try Self.analysis()
        let chosen = Array(analysis.top.suffix(from: analysis.top.count > 1 ? 1 : 0))
        let plan = NextSessionPlan.chosen(chosen, from: analysis, lapNumber: 2)
        #expect(plan.experiments.map(\.cornerLabel) == chosen.map(\.corner.label))
        #expect(plan.experiments.map(\.text) == chosen.map(\.note.suggestion))
        #expect(plan.fromLap == 2)
        #expect(plan.referencePhrase == analysis.referencePhrase)
        #expect(NextSessionPlan.chosen([], from: analysis, lapNumber: 2).experiments.isEmpty)
    }

    // MARK: - A plan kept with the circuit, with or without a project

    func temporaryLibrary() -> TrackLibrary {
        TrackLibrary(
            directory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("walkthrough-tracks-\(UUID().uuidString)"))
    }

    static let plan = NextSessionPlan(
        experiments: [PlannedExperiment(cornerLabel: "4", text: "Brake where lap 5 did.")], fromLap: 2,
        referencePhrase: "your best lap", made: Date(timeIntervalSince1970: 1_800_000_000))

    @Test func aPlanForANewCircuitIsKeptWithNothingElse() throws {
        let library = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library.directory) }
        try library.remember(Self.plan, id: "Q1") {
            TrackDefinition(circuitID: "Q1", name: "Sonoma Raceway", latitude: 38.16, longitude: -122.45)
        }
        let saved = try #require(library.definition(id: "Q1"))
        #expect(saved.plan == Self.plan)
        // A plan alone says nothing of the circuit's shape: a new file there is set up as if there
        // were no definition, its start/finish suggested from the trace.
        #expect(!saved.hasGeometry)
    }

    @Test func aPlanJoinsWhatTheCircuitAlreadyKnows() throws {
        let library = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library.directory) }
        let line = LapLineSpec(latitude: 38.16, longitude: -122.45, headingDegrees: 90)
        try library.save(
            TrackDefinition(
                circuitID: "Q1", name: "Sonoma Raceway", latitude: 38.16, longitude: -122.45, startFinish: line,
                cornerLabels: ["1", "2", "3a"]))
        var asked = false
        try library.remember(Self.plan, id: "Q1") {
            asked = true
            return nil
        }
        #expect(!asked, "A circuit with a definition was given a fresh one")
        let saved = try #require(library.definition(id: "Q1"))
        #expect(saved.plan == Self.plan)
        #expect(saved.startFinish == line)
        #expect(saved.cornerLabels == ["1", "2", "3a"])
        #expect(saved.hasGeometry)
    }

    @Test func noCircuitNoPlanKept() throws {
        let library = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library.directory) }
        try library.remember(Self.plan, id: "unknown") { nil }
        #expect(library.definition(id: "unknown") == nil)
    }
}
