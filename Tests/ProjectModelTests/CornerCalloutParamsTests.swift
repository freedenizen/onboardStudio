import Foundation
import Testing

@testable import ProjectModel

@Suite("Corner callout params")
struct CornerCalloutParamsTests {
    @Test func defaultsFillWhatAFileLeavesOut() throws {
        let decoded = try JSONDecoder().decode(CornerCalloutParams.self, from: Data("{}".utf8))
        #expect(decoded == CornerCalloutParams())
        let partial = try JSONDecoder().decode(CornerCalloutParams.self, from: Data(#"{"leadSeconds": 5}"#.utf8))
        #expect(partial.leadSeconds == 5)
        #expect(partial.holdSeconds == 2)
        #expect(partial.showSuggestion)
    }

    @Test func theKindRoundTripsAndKnowsItself() throws {
        var params = CornerCalloutParams()
        params.onlyOpportunities = true
        params.leadSeconds = 4
        let object = DisplayObject(label: "Callout", inputID: nil, frame: .full, kind: .cornerCallout(params))
        let data = try JSONEncoder().encode(object)
        let back = try JSONDecoder().decode(DisplayObject.self, from: data)
        #expect(back.kind == .cornerCallout(params))
        #expect(back.kind.typeName == "Corner Callout")
        #expect(back.kind.needsData)
        #expect(back.kind.isOverlay)
        #expect(DisplayObject.templates.contains { $0.0 == "Corner Callout" })
        // A project with one needs the coaching read at compile; one without does not.
        var project = Project(displayObjects: [object])
        #expect(project.needsCoaching)
        project.displayObjects = []
        #expect(!project.needsCoaching)
    }
}
