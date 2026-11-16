import Foundation
import ProjectModel
import TelemetryKit
import Testing

@testable import MediaKit

/// #555: a file added to the Logbook with poor positions says so in the import sheet's line.
@Suite("GPS in the Logbook's import lines (#555)")
struct TrackDayImportGPSTests {
    func line(rating: GPSQuality.Rating?) -> String {
        var entry = LogbookEntry(file: .init(path: "/s.csv", contentHash: "s", byteCount: 1, importerID: "rc"))
        entry.trackName = "Sonoma"
        entry.gps = rating.map { rating in
            GPSQuality(
                rateHertz: 1, precisionMeters: 15,
                findings: rating == .good ? [] : [.init(.rate(hertz: 1, wanted: 10), rating)])
        }
        return TrackDayImport.Report(url: URL(fileURLWithPath: "/s.csv"), outcome: .added(entry)).line
    }

    @Test func poorOrFairPositionsAreSaid() {
        #expect(line(rating: .poor) == "s.csv — added: Sonoma, no laps, GPS poor")
        #expect(line(rating: .fair) == "s.csv — added: Sonoma, no laps, GPS fair")
    }

    @Test func goodOrNoPositionsSayNothing() {
        #expect(line(rating: .good) == "s.csv — added: Sonoma, no laps")
        #expect(line(rating: nil) == "s.csv — added: Sonoma, no laps")
    }
}
