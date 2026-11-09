import Foundation
import Importers
import ProjectModel
import TelemetryKit
import Testing

@testable import MediaKit

@Suite("Logbook keys at compile (#351)", .serialized)
struct LogbookDerivedTests {
    @Test func textKeysAndThePersonalBestComeFromTheLogbook() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "derived-\(UUID().uuidString)")
        let logbook = Logbook(directory: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixture = CornerExportsTests.fixture
        let session = try RaceRenderCSVImporter().importSession(at: fixture, options: SessionBuilder.Options())
        var entry = try LogbookEntry.make(
            session: session, file: fixture, importerID: "racerender-csv", circuitID: nil, car: "Miata")
        entry.date = Date(timeIntervalSince1970: 1_700_000_000)
        try logbook.save(entry)
        // Scoped to this test's task (#431): repointing the process-wide logbook raced the suites
        // that run alongside.
        try await ProjectCompiler.$scopedLogbookDirectory.withValue(folder) {

            let data = Input(label: "d", source: MediaReference(path: fixture.path), kind: .data(DataInputSettings()))
            let text = DisplayObject(
                label: "T", inputID: nil, frame: .full, kind: .text(TextParams(text: "PB {pb} · {visits} visits")))
            let timer = DisplayObject(
                label: "D", inputID: data.id, frame: .full,
                kind: .timer(TimerParams(mode: .deltaToBest, deltaReference: .personalBest)))
            var project = Project(inputs: [data], displayObjects: [text, timer])
            project.details.car = "Miata"
            let loaded = try await ProjectCompiler.load(
                project, location: ProjectLocation(URL(fileURLWithPath: "/tmp/x.onboardproj")))
            #expect(loaded.derivedDetails["pb"] == "0:41.20")
            #expect(loaded.derivedDetails["visits"] == "1")
            #expect(loaded.derivedDetails["pbCar"] == "Miata")
            // The personal best is this very session, so the timer keeps measuring the session best.
            #expect(loaded.personalBests.isEmpty)
            // A project naming no key and no personal-best timer reads nothing.
            let plain = try await ProjectCompiler.load(
                Project(inputs: [data]), location: ProjectLocation(URL(fileURLWithPath: "/tmp/x.onboardproj")))
            #expect(plain.derivedDetails.isEmpty && plain.personalBests.isEmpty)
        }
    }

    @Test func aScopedLogbookIsSeenOnlyByItsOwnTask() async {
        // Two tests at once each see their own folder, and the process-wide one is untouched (#431).
        let before = ProjectCompiler.logbookDirectory
        let seen = await withTaskGroup(of: (Int, URL?).self) { group in
            for index in 0..<8 {
                group.addTask {
                    let folder = URL(fileURLWithPath: "/tmp/scoped-\(index)")
                    return await ProjectCompiler.$scopedLogbookDirectory.withValue(folder) {
                        await Task.yield()
                        return (index, ProjectCompiler.effectiveLogbookDirectory)
                    }
                }
            }
            return await group.reduce(into: [:]) { $0[$1.0] = $1.1 }
        }
        #expect(seen.count == 8)
        #expect(seen.allSatisfy { $0.value.path == "/tmp/scoped-\($0.key)" })
        #expect(ProjectCompiler.logbookDirectory == before)
    }
}
