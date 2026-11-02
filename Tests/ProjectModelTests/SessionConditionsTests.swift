import Foundation
import Testing

@testable import ProjectModel

@Suite("Session conditions (#348)")
struct SessionConditionsTests {
    @Test func conditionsRoundTripAndSummarise() throws {
        var entry = LogbookEntry(file: .init(path: "/tmp/s.csv", contentHash: "a", byteCount: 1, importerID: "x"))
        #expect(entry.conditions.isEmpty && entry.conditions.summary.isEmpty)
        entry.conditions = SessionConditions(
            weather: .sunny, track: .dry, ambientCelsius: 24.4, tyres: "RE-71RS", setup: "-1° camber")
        #expect(entry.conditions.summary == "Sunny · Dry · 24 °C · RE-71RS")
        let data = try Logbook.encoder.encode(entry)
        let back = try Logbook.decoder.decode(LogbookEntry.self, from: data)
        #expect(back.conditions == entry.conditions)
        // Partly filled in: only what is there.
        #expect(SessionConditions(track: .wet).summary == "Wet")
        #expect(SessionConditions(ambientCelsius: 9.6).summary == "10 °C")
    }

    @Test func olderEntriesAndUnknownWordsReadAsNotNoted() throws {
        let older = """
            { "file": { "path": "/tmp/s.csv", "contentHash": "a", "byteCount": 1, "importerID": "x" } }
            """
        let entry = try Logbook.decoder.decode(LogbookEntry.self, from: Data(older.utf8))
        #expect(entry.conditions.isEmpty)
        // A weather word a later build added reads as not noted rather than failing the entry.
        let future = """
            { "file": { "path": "/tmp/s.csv", "contentHash": "a", "byteCount": 1, "importerID": "x" },
              "conditions": { "weather": "hail", "track": "dry", "tyres": "slicks" } }
            """
        let read = try Logbook.decoder.decode(LogbookEntry.self, from: Data(future.utf8))
        #expect(read.conditions.weather == nil)
        #expect(read.conditions.track == .dry)
        #expect(read.conditions.tyres == "slicks")
    }
}
