import Foundation
import TelemetryKit
import Testing

@testable import ProjectModel

/// #584: definitions that ship with the app sit behind the driver's own.
@Suite("Track definitions that ship with the app")
struct TrackLibraryBuiltInTests {
    /// A driver's folder and a shipped folder, both empty, removed after the test.
    final class Folders {
        let root = FileManager.default.temporaryDirectory.appending(path: "builtin-\(UUID().uuidString)")
        var yours: URL { root.appending(path: "yours") }
        var shipped: URL { root.appending(path: "shipped") }
        var library: TrackLibrary { TrackLibrary(directory: yours, builtIn: shipped) }

        init() throws {
            try FileManager.default.createDirectory(at: shipped, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        /// Puts `definition` in the shipped folder as the app's bundle has it.
        func ship(_ definition: TrackDefinition) throws {
            try TrackLibrary.write(
                definition,
                to: shipped.appending(path: "\(TrackDefinition.slug(definition.id)).\(TrackLibrary.fileExtension)"))
        }
    }

    static let turn = TurnName(label: "3a", latitude: 47.001, longitude: 11.002)

    static var shipped: TrackDefinition {
        TrackDefinition(
            circuitID: "Q1", name: "Test Raceway", latitude: 47, longitude: 11,
            startFinish: LapLineSpec(latitude: 47, longitude: 11, headingDegrees: 90), turnNames: [turn])
    }

    @Test func aShippedDefinitionIsReadWhenTheDriverHasNone() throws {
        let folders = try Folders()
        try folders.ship(Self.shipped)
        let library = folders.library
        #expect(library.definition(id: "Q1")?.turnNames == [Self.turn])
        #expect(library.source(of: "Q1") == .builtIn)
        #expect(library.shipsDefinition(id: "Q1"))
        #expect(library.all().map(\.id) == ["Q1"])
        #expect(library.configurations(of: "Q1").map(\.id) == ["Q1"])
        #expect(library.source(of: "Q2") == nil)
    }

    @Test func theDriversOwnWins() throws {
        let folders = try Folders()
        try folders.ship(Self.shipped)
        var own = Self.shipped
        own.turnNames = [TurnName(label: "4", latitude: 47.001, longitude: 11.002)]
        try folders.library.save(own)
        #expect(folders.library.definition(id: "Q1")?.turnNames.map(\.label) == ["4"])
        #expect(folders.library.source(of: "Q1") == .yours)
        #expect(folders.library.shipsDefinition(id: "Q1"))
        #expect(folders.library.all().map(\.id) == ["Q1"], "one definition per circuit, the driver's")
    }

    @Test func aPlanIsKeptOnTheDriversCopyOfAShippedDefinition() throws {
        let folders = try Folders()
        try folders.ship(Self.shipped)
        let plan = NextSessionPlan(experiments: [PlannedExperiment(cornerLabel: "3a", text: "Brake later.")])
        try folders.library.remember(plan, id: "Q1") { nil }
        let kept = try #require(folders.library.definition(id: "Q1"))
        #expect(kept.plan == plan)
        #expect(kept.turnNames == [Self.turn], "the copy starts from the shipped definition")
        #expect(folders.library.source(of: "Q1") == .yours)
        // The shipped folder is never written.
        let shippedNow = try TrackLibrary.read(
            from: folders.shipped.appending(path: "q1.\(TrackLibrary.fileExtension)"))
        #expect(shippedNow.plan == nil)
    }

    @Test func forgettingTheDriversOwnBringsBackTheShippedOne() throws {
        let folders = try Folders()
        try folders.ship(Self.shipped)
        var own = Self.shipped
        own.turnNames = []
        try folders.library.save(own)
        try folders.library.remove(id: "Q1")
        #expect(folders.library.source(of: "Q1") == .builtIn)
        #expect(folders.library.definition(id: "Q1")?.turnNames == [Self.turn])
    }

    @Test func aLibraryReadsNothingShippedUnlessAsked() throws {
        let folders = try Folders()
        try folders.ship(Self.shipped)
        let plain = TrackLibrary(directory: folders.yours)
        #expect(plain.builtIn == nil)
        #expect(plain.definition(id: "Q1") == nil)
        #expect(!plain.shipsDefinition(id: "Q1"))
    }
}

/// What ships in `Sources/ProjectModel/Resources/Tracks`: every file reads, is filed under its own
/// id, is at a circuit the catalogue knows, says something about the circuit, carries no driver's
/// plan, and is listed with who made it in the folder's README.
@Suite("The shipped track definitions")
struct TrackLibraryBundleTests {
    @Test func everyShippedDefinitionIsSoundAndListed() throws {
        let folder = try #require(TrackLibrary.bundled, "the Tracks folder is bundled with ProjectModel")
        let readme = try String(contentsOf: folder.appending(path: "README.md"), encoding: .utf8)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == TrackLibrary.fileExtension }
        for file in files {
            let definition = try TrackLibrary.read(from: file)
            #expect(
                file.lastPathComponent == "\(TrackDefinition.slug(definition.id)).\(TrackLibrary.fileExtension)",
                "\(file.lastPathComponent) is not filed under its id")
            let circuit = try #require(definition.circuitID, "\(file.lastPathComponent) names no circuit")
            #expect(CircuitCatalog.circuit(id: circuit) != nil, "\(circuit) is not in the catalogue")
            #expect(definition.hasGeometry, "\(file.lastPathComponent) says nothing about the circuit")
            #expect(definition.plan == nil, "\(file.lastPathComponent) carries a driver's plan")
            #expect(readme.contains("`\(file.lastPathComponent)`"), "\(file.lastPathComponent) is not in the README")
            // MIT asks for its notice to travel with what it covers.
            if definition.credit?.hasPrefix("LapViz") == true {
                #expect(FileManager.default.fileExists(atPath: folder.appending(path: "LICENSE-LapViz.md").path))
            }
        }
    }
}
