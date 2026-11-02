import Foundation
import Importers
import ProjectModel
import TelemetryKit
import Testing

@testable import MediaKit

@Suite("Car against car (#354)", .serialized)
struct CarVersusCarTests {
    struct TwoCars {
        var first: LogbookEntry
        var second: LogbookEntry
        var folder: URL
    }

    /// Two sessions at the same place: the coaching fixture, and a copy one row shorter.
    func twoCars() throws -> TwoCars {
        let fixture = CornerExportsTests.fixture
        let folder = FileManager.default.temporaryDirectory.appending(path: "cars-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appending(path: "coaching-laps.csv")
        let text = try String(contentsOf: fixture, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        try lines.dropLast(2).joined(separator: "\n").write(to: copy, atomically: true, encoding: .utf8)
        let importer = RaceRenderCSVImporter()
        let a = try LogbookEntry.make(
            session: try importer.importSession(at: fixture, options: SessionBuilder.Options()), file: fixture,
            importerID: "racerender-csv", circuitID: nil, car: "Miata")
        let b = try LogbookEntry.make(
            session: try importer.importSession(at: copy, options: SessionBuilder.Options()), file: copy,
            importerID: "racerender-csv", circuitID: nil, car: "GR86")
        return TwoCars(first: a, second: b, folder: folder)
    }

    @Test func bothBestLapsAreReadAndSentencedCornerByCorner() throws {
        let cars = try twoCars()
        let (first, second) = (cars.first, cars.second)
        defer { try? FileManager.default.removeItem(at: cars.folder) }
        let comparison = try #require(
            CarVersusCar.make(first: first, firstCar: "Miata", second: second, secondCar: "GR86"))
        #expect(comparison.first.car == "Miata" && comparison.second.car == "GR86")
        #expect(comparison.analysis.referencePhrase == "the GR86's best lap")
        #expect(comparison.analysis.corners.count == 2)
        #expect(comparison.analysis.delta.alignment == .byPosition)
        let sentences = comparison.sentences
        #expect(sentences.count == 2)
        #expect(sentences[0].hasPrefix("Turn 1: "))
        #expect(sentences.allSatisfy { $0.contains("Miata") || $0.contains("GR86") || $0.contains("level") })
        #expect(comparison.headline.contains("best lap"))
        let traces = comparison.speedTraces(count: 100)
        #expect(Set(traces.map(\.car)) == ["Miata", "GR86"])
        #expect(traces.count > 100 && traces.count < 260)
        #expect(traces.allSatisfy { $0.speed > 0 && $0.distance >= 0 })
        // A session the logbook cannot read is no comparison.
        var gone = second
        gone.file.path = "/nowhere/coaching-laps.csv"
        gone.file.bookmark = nil
        #expect(CarVersusCar.make(first: first, firstCar: "Miata", second: gone, secondCar: "GR86") == nil)
    }
}
