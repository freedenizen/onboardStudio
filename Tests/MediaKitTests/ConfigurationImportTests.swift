import Foundation
import Importers
import ProjectModel
import TelemetryKit
import Testing

@testable import MediaKit

/// #549 through the files: a session entered in the logbook is filed under the configuration whose
/// named turns it drives, and its corners are read by that configuration's names.
@Suite("Filing a session under its configuration (#549)", .serialized)
struct ConfigurationImportTests {
    static let csv = TrackDayImportTests.fixtures.appending(path: "coaching-laps-at-circuit.csv")

    func scratch(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString)")
    }

    @Test func aSessionIsFiledUnderTheConfigurationItDroveAndTakesItsNames() async throws {
        let session = try FormatDetector.importSession(at: Self.csv, options: SessionBuilder.Options())
        let circuit = try #require(CircuitCatalog.identify(session)).circuit
        let best = try #require(LapDeltas.sessionBest(in: session))
        let profile = try #require(LapProfile(lap: best, in: session))
        let corners = CornerDetector.corners(of: profile)
        try #require(!corners.isEmpty)
        // Invented names for the turns the fixture drives, on a configuration of their own, and an
        // unnamed configuration whose turns are somewhere else entirely.
        let names = corners.enumerated().compactMap { TurnName(label: "C\($0.offset + 1)", corner: $0.element) }
        let tracks = TrackLibrary(directory: scratch("tracks"))
        try tracks.save(
            TrackDefinition(
                circuitID: circuit.id, configuration: "Club", name: circuit.name, latitude: 0, longitude: 0,
                turnNames: names))
        try tracks.save(
            TrackDefinition(
                circuitID: circuit.id, name: circuit.name, latitude: 0, longitude: 0,
                turnNames: [TurnName(label: "X", latitude: 0, longitude: 0)]))
        let logbook = Logbook(directory: scratch("logbook"))
        _ = await TrackDayImport.run([Self.csv], into: logbook, tracks: tracks)
        let entry = try #require(logbook.entries().first)
        #expect(entry.configuration == "Club")
        #expect(LogbookFilter.circuitKey(of: entry) == CircuitKey.make(circuit.id, configuration: "Club"))
        #expect(entry.corners.map(\.label) == names.map(\.label))
        // Read again from the file, it keeps them.
        let again = try #require(LogbookReferences.load(entry, tracks: tracks))
        #expect(again.turnNames == names)
    }

    @Test func withoutConfigurationsASessionGoesWhereItAlwaysWent() async throws {
        let logbook = Logbook(directory: scratch("logbook"))
        _ = await TrackDayImport.run([Self.csv], into: logbook, tracks: TrackLibrary(directory: scratch("tracks")))
        let entry = try #require(logbook.entries().first)
        #expect(entry.configuration == nil)
        #expect(entry.circuitID.map { LogbookFilter.circuitKey(of: entry) == $0 } == true)
    }
}
