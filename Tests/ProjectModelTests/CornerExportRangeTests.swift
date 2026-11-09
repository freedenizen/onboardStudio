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

    @Test func aCornerExportSavedBeforeRetimesPlaysAtSpeed() throws {
        // As 0.35 wrote it: no retime.
        let old = Data(#"{"eachCorner":{"onlyOpportunities":true}}"#.utf8)
        #expect(
            try JSONDecoder().decode(ExportRange.self, from: old) == .eachCorner(onlyOpportunities: true, retime: nil))
        // A fresh choice slows the braking zone to half and holds a second, and survives a save.
        let range = ExportRange.eachCorner(onlyOpportunities: false, retime: .standard)
        #expect(try JSONDecoder().decode(ExportRange.self, from: JSONEncoder().encode(range)) == range)
        #expect(CornerClipRetime.standard.brakingRate == 0.5 && CornerClipRetime.standard.referenceHoldSeconds == 1)
    }
}
