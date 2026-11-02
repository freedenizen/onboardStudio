import Foundation
import Testing

@testable import ProjectModel

@Suite("Every-corner export range")
struct CornerExportRangeTests {
    @Test func theRangeRoundTripsAndAsksForTheCoachingRead() throws {
        var settings = ExportSettings.hd1080
        settings.range = .eachCorner(onlyOpportunities: true)
        let back = try JSONDecoder().decode(ExportSettings.self, from: try JSONEncoder().encode(settings))
        #expect(back.range == .eachCorner(onlyOpportunities: true))
        var project = Project()
        #expect(!project.needsCoaching)
        project.export.range = .eachCorner(onlyOpportunities: false)
        #expect(project.needsCoaching)
    }
}
