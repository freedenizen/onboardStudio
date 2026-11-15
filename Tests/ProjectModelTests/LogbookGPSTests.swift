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

/// #555: the thresholds GPS is rated against are the driver's, kept in Settings.
@Suite("GPS thresholds in Settings (#555)")
struct GPSThresholdsTests {
    @Test func theDefaultsAreKeptAsNothing() {
        #expect(GPSQuality.Options().preferenceText.isEmpty)
        #expect(GPSQuality.Options(preferenceText: "") == GPSQuality.Options())
        #expect(GPSQuality.Options(preferenceText: "not json") == GPSQuality.Options())
    }

    @Test func aChangedThresholdIsKeptAndReadBack() {
        var options = GPSQuality.Options()
        options.goodRateHertz = 20
        options.poorSatellites = 4
        #expect(options.preferenceText == #"{"goodRateHertz":20,"poorSatellites":4}"#)
        #expect(GPSQuality.Options(preferenceText: options.preferenceText) == options)
        #expect(Preferences.allKeys.contains(Preferences.gpsThresholds.key))
    }

    @Test func storedMeasurementsAreRatedAgainstTheThresholdsInForce() {
        let measured = GPSQuality(rateHertz: 10, precisionMeters: 1)
        #expect(measured.rated(with: .init()).rating == .good)
        var strict = GPSQuality.Options()
        strict.goodRateHertz = 20
        let rated = measured.rated(with: strict)
        #expect(rated.rating == .fair)
        #expect(rated.messages(units: .metric) == ["Only 10 positions a second; corner-level advice needs 20 or more."])
    }
}
