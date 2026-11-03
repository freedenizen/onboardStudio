import Foundation
import Testing

@testable import ProjectModel

@Suite("Projects and the logbook (#349)")
struct LogbookLinkTests {
    @Test func aDataInputRemembersItsEntryAndOlderFilesHaveNone() throws {
        var settings = DataInputSettings()
        #expect(settings.logbookEntryID == nil)
        let id = UUID()
        settings.logbookEntryID = id
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(DataInputSettings.self, from: data).logbookEntryID == id)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["logbookEntryID"] = nil
        let olderData = try JSONSerialization.data(withJSONObject: json)
        let older = try JSONDecoder().decode(DataInputSettings.self, from: olderData)
        #expect(older.logbookEntryID == nil)
        // The preference is on unless turned off.
        #expect(Preferences.logbookAutoAdd.unset == true)
    }

    @Test func anEntryListsItsProjectsAndExports() throws {
        var entry = LogbookEntry(file: .init(path: "/tmp/s.csv", contentHash: "a", byteCount: 1, importerID: "x"))
        #expect(entry.exports.isEmpty)
        entry.projects = [.init(path: "/days/sonoma.onboardproj", name: "sonoma")]
        entry.exports = [.init(path: "/days/sonoma.mp4", name: "sonoma.mp4")]
        let back = try Logbook.decoder.decode(LogbookEntry.self, from: try Logbook.encoder.encode(entry))
        #expect(back.projects == entry.projects && back.exports == entry.exports)
        let older = """
            { "file": { "path": "/tmp/s.csv", "contentHash": "a", "byteCount": 1, "importerID": "x" } }
            """
        #expect(try Logbook.decoder.decode(LogbookEntry.self, from: Data(older.utf8)).exports.isEmpty)
    }
}
