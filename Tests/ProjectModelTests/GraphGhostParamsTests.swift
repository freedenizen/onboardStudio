import Foundation
import Testing

@testable import ProjectModel

@Suite("Graph ghost params")
struct GraphGhostParamsTests {
    @Test func theBestLapRemainsTheGhostForOlderFiles() throws {
        let older = try JSONDecoder().decode(GraphParams.self, from: Data(#"{"series": []}"#.utf8))
        #expect(older.ghost == .bestLap)
        var params = GraphParams(series: [GraphSeries(channel: "speed")], axis: .lap)
        params.ghost = .coachingReference
        let back = try JSONDecoder().decode(GraphParams.self, from: try JSONEncoder().encode(params))
        #expect(back.ghost == .coachingReference)
        // Only a lap-axis graph with the coaching reference as its ghost asks for the coaching read.
        let graph = DisplayObject(label: "G", inputID: nil, frame: .full, kind: .graph(params))
        #expect(Project(displayObjects: [graph]).needsCoaching)
        params.ghost = .bestLap
        let plain = DisplayObject(label: "G", inputID: nil, frame: .full, kind: .graph(params))
        #expect(!Project(displayObjects: [plain]).needsCoaching)
    }
}
