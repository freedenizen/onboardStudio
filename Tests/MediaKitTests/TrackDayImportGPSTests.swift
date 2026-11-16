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
        // Rated against the thresholds in Settings when shown: the measurements decide.
        let hertz: [GPSQuality.Rating: Double] = [.good: 25, .fair: 7, .poor: 1]
        entry.gps = rating.map { GPSQuality(rateHertz: hertz[$0] ?? 25, precisionMeters: 1) }
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
