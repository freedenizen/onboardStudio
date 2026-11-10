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

    /// #462: Coach… in the Logbook finds the project open on a session by this.
    @Test func aDataInputIsItsEntrysSessionByTheEntryItRemembersElseByItsFile() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "logbook-link-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "session.csv")
        let other = folder.appending(path: "other.csv")
        try Data("a".utf8).write(to: file)
        try Data("b".utf8).write(to: other)
        let entry = LogbookEntry(file: .init(path: file.path, contentHash: "a", byteCount: 1, importerID: "x"))

        func input(remembering id: UUID?) -> Input {
            var settings = DataInputSettings()
            settings.logbookEntryID = id
            return Input(label: "session", source: MediaReference(path: file.path), kind: .data(settings))
        }
        // The entry it remembers decides, wherever the file is said to be.
        #expect(entry.isSession(of: input(remembering: entry.id), at: other))
        #expect(!entry.isSession(of: input(remembering: UUID()), at: file))
        // Remembering none, it is the session when its file is the entry's — by any spelling of the path.
        #expect(entry.isSession(of: input(remembering: nil), at: file))
        #expect(entry.isSession(of: input(remembering: nil), at: folder.appending(path: "sub/../session.csv")))
        #expect(!entry.isSession(of: input(remembering: nil), at: other))
        // A video is nobody's session.
        let video = Input(label: "clip", source: MediaReference(path: file.path), kind: .video(VideoInputSettings()))
        #expect(!entry.isSession(of: video, at: file))
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
