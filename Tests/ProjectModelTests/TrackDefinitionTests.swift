import Foundation
import Testing

@testable import ProjectModel

@Suite("Track definitions")
struct TrackDefinitionTests {
    static func sonoma() -> TrackDefinition {
        TrackDefinition(
            circuitID: "Q112563", name: "Sonoma Raceway", latitude: 38.16083, longitude: -122.455,
            startFinish: LapLineSpec(latitude: 38.16155, longitude: -122.45467, headingDegrees: 308),
            sectors: SectorSpec(mode: .cornerAware, count: 3),
            cornerLabels: ["1", "2", "3", "3a", "4", "4a"])
    }

    @Test func aDefinitionIsFiledUnderItsWikidataID() {
        #expect(Self.sonoma().id == "Q112563")
    }

    @Test func aVenueTheListDoesNotHaveIsFiledUnderItsName() {
        // A club circuit, a car park, an airfield: no Wikidata item, but still worth remembering.
        let definition = TrackDefinition(name: "Blyton Park — Eastern", latitude: 53.46, longitude: -0.71)
        #expect(definition.id == "blyton-park-eastern")
    }

    @Test func slugsAreStableAndSafeAsFileNames() {
        #expect(TrackDefinition.slug("Sonoma Raceway") == "sonoma-raceway")
        #expect(TrackDefinition.slug("Nürburgring") == "nurburgring")
        #expect(TrackDefinition.slug("Circuit de Spa-Francorchamps") == "circuit-de-spa-francorchamps")
        // Punctuation collapses rather than producing a run of separators or a trailing one.
        #expect(TrackDefinition.slug("  Brands Hatch // Indy  ") == "brands-hatch-indy")
        #expect(TrackDefinition.slug("///") == "track")
        #expect(TrackDefinition.slug("").isEmpty == false)
        #expect(TrackDefinition.slug(String(repeating: "a", count: 200)).count == 64)
    }

    @Test func roundTripsThroughJSON() throws {
        let original = Self.sonoma()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TrackDefinition.self, from: try encoder.encode(original))
        #expect(decoded.circuitID == original.circuitID)
        #expect(decoded.name == original.name)
        #expect(decoded.startFinish?.headingDegrees == 308)
        #expect(decoded.sectors.mode == .cornerAware)
        // The reason corner names are strings: Sonoma's fourth corner is called 3a.
        #expect(decoded.cornerLabels == ["1", "2", "3", "3a", "4", "4a"])
    }

    @Test func aDefinitionMissingEverythingOptionalStillDecodes() throws {
        // A hand-written or older file: it should load with sensible values rather than throw.
        let decoded = try JSONDecoder().decode(TrackDefinition.self, from: Data("{}".utf8))
        #expect(decoded.name == "Track")
        #expect(decoded.circuitID == nil)
        #expect(decoded.startFinish == nil)
        #expect(decoded.sectors == SectorSpec())
        #expect(decoded.cornerLabels.isEmpty)
    }
}

@Suite("Track library")
struct TrackLibraryTests {
    func temporaryLibrary() -> TrackLibrary {
        TrackLibrary(
            directory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "onboard-tracks-\(UUID().uuidString)"))
    }

    @Test func savingThenReadingBack() throws {
        let library = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library.directory) }
        try library.save(TrackDefinitionTests.sonoma())
        let read = try #require(library.definition(id: "Q112563"))
        #expect(read.name == "Sonoma Raceway")
        #expect(read.startFinish?.latitude == 38.16155)
        // Saving stamps the time, so two drivers can tell whose copy is newer.
        #expect(read.modified.timeIntervalSinceNow > -60)
    }

    @Test func savingTwiceReplacesRatherThanDuplicating() throws {
        let library = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library.directory) }
        try library.save(TrackDefinitionTests.sonoma())
        var updated = TrackDefinitionTests.sonoma()
        updated.sectors = SectorSpec(mode: .equalDistance, count: 5)
        try library.save(updated)
        #expect(library.all().count == 1)
        #expect(library.definition(id: "Q112563")?.sectors.count == 5)
    }

    @Test func anEmptyOrMissingLibraryIsEmptyRatherThanAnError() {
        let library = temporaryLibrary()
        #expect(library.all().isEmpty)
        #expect(library.definition(id: "Q112563") == nil)
        // Removing something that is not there is not an error either.
        #expect(throws: Never.self) { try library.remove(id: "Q112563") }
    }

    @Test func removingADefinition() throws {
        let library = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library.directory) }
        try library.save(TrackDefinitionTests.sonoma())
        try library.remove(id: "Q112563")
        #expect(library.definition(id: "Q112563") == nil)
    }

    @Test func listingIsNewestFirst() throws {
        let library = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library.directory) }
        // Written rather than saved, because `save` stamps the time itself and two saves in the
        // same millisecond would leave the order to chance.
        try FileManager.default.createDirectory(at: library.directory, withIntermediateDirectories: true)
        let old = TrackDefinition(
            name: "Older", latitude: 1, longitude: 1, modified: Date(timeIntervalSince1970: 1000))
        let new = TrackDefinition(
            name: "Newer", latitude: 2, longitude: 2, modified: Date(timeIntervalSince1970: 2000))
        try TrackLibrary.write(old, to: library.url(for: old.id))
        try TrackLibrary.write(new, to: library.url(for: new.id))
        #expect(library.all().map(\.name) == ["Newer", "Older"])
    }

    @Test func somethingUnreadableInTheDirectoryIsSkipped() throws {
        let library = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library.directory) }
        try library.save(TrackDefinition(name: "Real", latitude: 1, longitude: 1))
        // A definition-shaped file that is not JSON, and a file that is not a definition at all.
        try Data("not json".utf8).write(to: library.url(for: "broken"))
        try Data("{}".utf8).write(to: library.directory.appending(path: "notes.txt"))
        #expect(library.all().map(\.name) == ["Real"])
    }

    @Test func aDefinitionIsAFileYouCanHandToSomebody() throws {
        let library = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library.directory) }
        try library.save(TrackDefinitionTests.sonoma())
        let file = library.url(for: "Q112563")
        #expect(file.pathExtension == TrackLibrary.fileExtension)
        #expect(FileManager.default.fileExists(atPath: file.path))
        // And it reads back on its own, away from any library.
        #expect(try TrackLibrary.read(from: file).name == "Sonoma Raceway")
    }
}
