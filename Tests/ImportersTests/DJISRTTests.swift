import Foundation
import Testing

@testable import Importers
@testable import TelemetryKit

@Suite("DJI SRT importer")
struct DJISRTTests {
    static func fixture(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appending(path: name)
    }

    @Test func readsMavicStyleCues() throws {
        let url = try Self.fixture("dji-mavic.srt")
        #expect(try FormatDetector.detect(url)?.id == "dji-srt")
        let table = try DJISRTImporter().importFile(at: url)
        #expect(table.rowCount == 3)
        #expect(table.times == [0, 0.033, 1.0])
        #expect(table.column(named: "Latitude")?.values.first == 45.123456)
        #expect(table.column(named: "Longitude")?.values.first == -122.654321)
        #expect(table.column(named: "Altitude")?.values.first == 100.2)
        #expect(table.column(named: "Height")?.values.last == 13.3)
        #expect(table.column(named: "ISO")?.values.last == 200)
        #expect(table.column(named: "Shutter")?.values.first == 1000)
        #expect(table.column(named: "Aperture")?.values.first == 2.8)
        // The first cue is stamped 14:05:10.123 local time, so time 0 of the log is that instant.
        let created = try #require(table.info.createdAt)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: created)
        #expect(parts.hour == 14 && parts.minute == 5 && parts.second == 10)
        #expect(abs(Double(parts.nanosecond ?? 0) / 1e9 - 0.123) < 0.002)
        let session = SessionBuilder.build(table)
        #expect(session.hasAbsoluteTime)
        #expect(session[.speed] != nil, "speed is derived from position")
    }

    @Test func readsOsmoStyleCues() throws {
        let url = try Self.fixture("dji-osmo.srt")
        #expect(try FormatDetector.detect(url)?.id == "dji-srt")
        let session = try DJISRTImporter().importSession(at: url)
        #expect(session[.latitude]?.values.first == 45.1234)
        #expect(session[.longitude]?.values.first == -122.6543)
        #expect(session[.altitude]?.values.first == 15)
        #expect(session[.speed]?.values.last == 6.0)
        #expect(session[.aux("Height")]?.values.first == 20)
        #expect(session[.aux("Home distance")]?.values.last == 30)
        #expect(session.timeRange?.upperBound == 2.0)
        #expect(session.hasAbsoluteTime)
    }

    @Test func plainSubtitlesAreNotTelemetry() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "plain-\(UUID().uuidString).srt")
        try "1\n00:00:01,000 --> 00:00:02,000\nHello there\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(DJISRTImporter.confidence(for: try FileSniff.sniff(url)) == .possible)
        #expect(throws: ImportError.noData) { try DJISRTImporter().importFile(at: url) }
    }
}
