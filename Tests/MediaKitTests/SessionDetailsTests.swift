import Foundation
import Importers
import MediaKit
import ProjectModel
import Testing

@testable import TelemetryKit

@Suite("Details a data file gives a project (#74)")
struct SessionDetailsTests {
    static func fixture(_ name: String) throws -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures/\(name)")
    }

    @Test func aRaceChronoFileNamesItsTrackDriverAndDay() throws {
        let session = try RaceChronoCSVImporter().importSession(at: Self.fixture("racechrono-v3.csv"))
        let details = ProjectDetails.suggested(by: session, circuitName: "Laguna Seca")
        // The file's own name for the place wins over the recognised circuit's.
        #expect(details.track == "Test Circuit")
        #expect(details.driver == "OnboardStudio")
        // Recorded at 02:54 UTC on 31 Dec 2025; the day is the driver's, in the local calendar, so
        // west of UTC−3 it is the 30th (#440).
        let recorded = try #require(session.info.createdAt)
        #expect(recorded == Date(timeIntervalSince1970: 1_767_149_640))
        #expect(details.date == ProjectDetails.iso(recorded))
        #expect(details.car.isEmpty && details.event.isEmpty)
    }

    @Test func aFileThatNamesNoTrackTakesTheRecognisedCircuit() {
        let session = TelemetrySession(info: SessionInfo(sourceFormat: "test", trackName: "  "), channels: [])
        #expect(ProjectDetails.suggested(by: session, circuitName: "Laguna Seca").track == "Laguna Seca")
        #expect(ProjectDetails.suggested(by: session).isEmpty)
    }
}
