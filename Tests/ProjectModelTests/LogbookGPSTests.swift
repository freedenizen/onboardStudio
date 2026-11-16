import Foundation
import Importers
import TelemetryKit
import Testing

@testable import ProjectModel

/// #555: a Logbook session keeps how far its positions can be trusted.
@Suite("GPS quality in the Logbook (#555)")
struct LogbookGPSTests {
    @Test func aSessionEnteredNowKeepsItsGPSQuality() throws {
        let session = try LapSplitsTests.session()
        let entry = try LogbookEntry.make(
            session: session, file: LapSplitsTests.fixture, importerID: "racerender-csv", circuitID: nil)
        #expect(entry.gps == session.gpsQuality)
        #expect(entry.gps != nil)
        #expect(!entry.needsGPSReading)
        #expect(entry.gpsRank == entry.gps?.rating.rawValue)
    }

    @Test func anEntryFromBeforeIsJudgedWhenNextShown() throws {
        let json = """
            {"file": {"path": "/c.csv", "contentHash": "c", "byteCount": 1, "importerID": "rc"},
             "laps": [{"number": 1, "seconds": 61.5, "isComplete": true}]}
            """
        let entry = try JSONDecoder().decode(LogbookEntry.self, from: Data(json.utf8))
        #expect(entry.gps == nil)
        #expect(entry.needsGPSReading)
        #expect(entry.gpsRank == 4, "after every judged session")

        var read = entry
        read.readGPS(of: try LapSplitsTests.session())
        let again = try JSONDecoder().decode(LogbookEntry.self, from: JSONEncoder().encode(read))
        #expect(again.gps == read.gps)
        #expect(!again.needsGPSReading)
    }

    @Test func aFileWithoutPositionsIsJudgedOnceAndHasNone() {
        var entry = LogbookEntry(file: .init(path: "/d.csv", contentHash: "d", byteCount: 1, importerID: "rc"))
        entry.readGPS(of: TelemetrySession(info: SessionInfo(sourceFormat: "test"), channels: []))
        #expect(entry.gps == nil)
        #expect(!entry.needsGPSReading, "not read again every time it is shown")
        #expect(entry.gpsRank == 3)
    }
}
