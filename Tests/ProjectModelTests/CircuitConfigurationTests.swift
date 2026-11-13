import Foundation
import Importers
import TelemetryKit
import Testing

@testable import ProjectModel

/// A circuit's configurations (#549). Coordinates and names are invented; the session is the
/// committed synthetic fixture.
@Suite("Circuit configurations")
struct CircuitConfigurationTests {
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/coaching-laps.csv")

    func entry(_ hash: String, configuration: String? = nil, car: String = "", best: Double? = nil) -> LogbookEntry {
        var entry = LogbookEntry(
            file: .init(path: "/d/\(hash).csv", contentHash: hash, byteCount: 1, importerID: "x"),
            circuitID: "Q1", date: Date(timeIntervalSince1970: 1_700_000_000), car: car, bestLap: best)
        entry.configuration = configuration
        return entry
    }

    // MARK: - The key

    @Test func theUnnamedConfigurationKeepsTheCircuitsOwnKey() {
        #expect(CircuitKey.make("Q1", configuration: nil) == "Q1")
        #expect(CircuitKey.make("Q1", configuration: "  ") == "Q1")
        #expect(CircuitKey.make("Q1", configuration: " Club Course ") == "Q1|Club Course")
        #expect(CircuitKey.make("", configuration: "Club Course").isEmpty, "no circuit, no configuration of it")
        #expect(CircuitKey.base(of: "Q1|Club Course") == "Q1")
        #expect(CircuitKey.base(of: "Q1") == "Q1")
        #expect(CircuitKey.configuration(of: "Q1|Club Course") == "Club Course")
        #expect(CircuitKey.configuration(of: "Q1") == nil)
        // The separator cannot get into a name, so a key always splits back the way it was made.
        #expect(CircuitKey.make("Q1", configuration: "A|B") == "Q1|A B")
        #expect(CircuitKey.title("Test Raceway", configuration: "Club Course") == "Test Raceway — Club Course")
        #expect(CircuitKey.title("Test Raceway", configuration: nil) == "Test Raceway")
    }

    @Test func aSessionIsKeyedByItsConfigurationAndAnOldOneIsNot() throws {
        #expect(LogbookFilter.circuitKey(of: entry("a")) == "Q1")
        #expect(LogbookFilter.circuitKey(of: entry("b", configuration: "Club")) == "Q1|Club")
        #expect(LogbookFilter.baseCircuitKey(of: entry("b", configuration: "Club")) == "Q1")
        // A session saved before #549 decodes with no configuration: the circuit as it was.
        let old = try Logbook.decoder.decode(
            LogbookEntry.self,
            from: Data(
                #"{"file":{"path":"/d/o.csv","contentHash":"o","byteCount":1,"importerID":"x"},"circuitID":"Q1"}"#.utf8)
        )
        #expect(old.configuration == nil)
        #expect(LogbookFilter.circuitKey(of: old) == "Q1")
        var club = entry("c", configuration: "Club")
        let back = try Logbook.decoder.decode(LogbookEntry.self, from: try Logbook.encoder.encode(club))
        #expect(back.configuration == "Club")
        club.configuration = nil
        #expect(LogbookEditName.of(back, club) == "Change Configuration")
    }

    @Test func eachConfigurationIsItsOwnCircuitInTheSidebarWithItsOwnBest() {
        let entries = [
            entry("a", best: 100), entry("b", best: 98), entry("c", configuration: "Club", best: 70),
        ]
        let groups = LogbookFilter.circuits(in: entries)
        let keys = groups.compactMap { group -> String? in
            guard case .circuit(let id, _) = group.scope else { return nil }
            return id
        }
        #expect(Set(keys) == ["Q1", "Q1|Club"])
        let club = groups.first { if case .circuit("Q1|Club", _) = $0.scope { true } else { false } }
        #expect(club?.scope.title.hasSuffix(" — Club") == true)
        // The shorter layout's lap is not the circuit's personal best, nor the other way round.
        #expect(PersonalBests.best(in: entries, circuitKey: "Q1")?.seconds == 98)
        #expect(PersonalBests.best(in: entries, circuitKey: "Q1|Club")?.seconds == 70)
    }

    @Test func aCarNamedLikeAConfigurationDoesNotShareItsBest() {
        // The car's best was kept under "circuit|car", which a configuration's key now looks like.
        let entries = [entry("a", car: "Club", best: 90), entry("b", configuration: "club", best: 60)]
        let badges = PersonalBests.badges(in: entries)
        #expect(badges[entries[0].id] == .current)
        #expect(badges[entries[1].id] == .current)
    }

    @Test func theConfigurationsNamedAtACircuitComeFromSessionsAndDefinitions() {
        let entries = [entry("a"), entry("b", configuration: "Club"), entry("c", configuration: "club ")]
        let definitions = [
            TrackDefinition(circuitID: "Q1", configuration: "Long", name: "Test", latitude: 0, longitude: 0),
            TrackDefinition(circuitID: "Q2", configuration: "Elsewhere", name: "Other", latitude: 0, longitude: 0),
        ]
        #expect(
            LogbookFilter.configurations(at: "Q1", in: entries, definitions: definitions) == ["club", "Club", "Long"])
        #expect(LogbookFilter.configurations(at: "", in: entries).isEmpty)
    }

    @Test func aDefinitionIsFiledBesideItsCircuitAndTheOldOneKeepsItsFile() throws {
        let old = TrackDefinition(circuitID: "Q1", name: "Test Raceway", latitude: 0, longitude: 0)
        let club = TrackDefinition(
            circuitID: "Q1", configuration: "Club Course", name: "Test Raceway", latitude: 0, longitude: 0)
        #expect(old.id == "Q1")
        #expect(club.id == "Q1|Club Course")
        #expect(club.title == "Test Raceway — Club Course")
        let directory = FileManager.default.temporaryDirectory.appending(path: "configurations-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = TrackLibrary(directory: directory)
        try library.save(old)
        try library.save(club)
        #expect(library.url(for: old.id) != library.url(for: club.id))
        #expect(library.definition(id: "Q1")?.configuration == nil)
        #expect(library.definition(id: "Q1|Club Course")?.configuration == "Club Course")
        #expect(Set(library.configurations(of: "Q1").map(\.id)) == ["Q1", "Q1|Club Course"])
        let decoded = try JSONDecoder().decode(TrackDefinition.self, from: Data(#"{"circuitID":"Q1"}"#.utf8))
        #expect(decoded.configuration == nil)
    }

    @Test func changingADaysCircuitMovesItsSessionsWhateverConfigurationTheyDrove() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "day-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let logbook = Logbook(directory: directory)
        let day = try logbook.day(on: Date(timeIntervalSince1970: 1_700_000_000), circuitID: "Q1")
        var club = entry("a", configuration: "Club")
        club.trackDayID = day.id
        try logbook.save(club)
        var moved = day
        moved.circuitID = "Q2"
        _ = try logbook.updateDay(moved)
        let after = try #require(logbook.entry(id: club.id))
        #expect(after.circuitID == "Q2")
    }

    // MARK: - Which configuration a session drove

    /// The fixture's best lap's corners, and names pinned to them.
    func turns(of session: TelemetrySession) throws -> [TurnName] {
        let best = try #require(LapDeltas.sessionBest(in: session))
        let profile = try #require(LapProfile(lap: best, in: session))
        let corners = CornerDetector.corners(of: profile)
        #expect(corners.count == 2)
        return corners.enumerated().compactMap { TurnName(label: "\($0.offset + 1)", corner: $0.element) }
    }

    func definition(_ configuration: String?, turns: [TurnName]) -> TrackDefinition {
        TrackDefinition(
            circuitID: "Q1", configuration: configuration, name: "Test", latitude: 0, longitude: 0, turnNames: turns)
    }

    /// A turn far from anything the fixture drives.
    let elsewhere = TurnName(label: "9", latitude: 10, longitude: 10)

    @Test func aSessionIsFiledUnderTheConfigurationWhoseTurnsItDrives() throws {
        let session = try RaceRenderCSVImporter().importSession(at: Self.fixture, options: SessionBuilder.Options())
        let turns = try turns(of: session)
        let club = definition("Club", turns: turns)
        let long = definition("Long", turns: [turns[0], elsewhere, elsewhere])
        #expect(ConfigurationMatch.configuration(of: session, among: [long, club]) == "Club")
        // The unnamed configuration matching best leaves the session where it always went.
        #expect(ConfigurationMatch.configuration(of: session, among: [definition(nil, turns: turns), long]) == nil)
        // Nothing agrees well enough: the unnamed configuration, for the driver to move it.
        #expect(ConfigurationMatch.configuration(of: session, among: [long]) == nil)
        // Two that agree equally are not the app's to choose between.
        let same = definition("Same", turns: turns)
        #expect(ConfigurationMatch.configuration(of: session, among: [club, same]) == nil)
        // Definitions without named turns cannot be told apart at all.
        #expect(ConfigurationMatch.configuration(of: session, among: [definition("Club", turns: [])]) == nil)
    }
}
