import Foundation
import Testing

@testable import MediaKit

/// What the editor says of a file it will not add as data, and what it lets through (#668).
@Suite("Adding a data file (#668)")
struct DataFileCheckTests {
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures")

    @Test(arguments: ["racechrono-v3.csv", "session.rcz", "session.vbo", "track.gpx", "generic.csv", "activity.tcx"])
    func aLoggersFileIsAdded(_ name: String) {
        #expect(DataFileCheck.refusal(of: Self.fixtures.appending(path: name)) == nil)
    }

    @Test func aFileNoImporterKnowsIsRefusedInWordsThatSayWhereToLook() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "data-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let notes = folder.appending(path: "notes.txt")
        try Data("Tyre pressures to try next time.\nBring the torque wrench.\n".utf8).write(to: notes)
        #expect(
            DataFileCheck.refusal(of: notes)
                == "“notes.txt” was not added: it is not a data file this app reads. "
                + "Help ▸ Supported Data Formats lists the ones it does.")
        // A picture is no logger's file either.
        #expect(DataFileCheck.refusal(of: Self.fixtures.appending(path: "arrow.png")) != nil)
    }

    @Test func aFileThatIsNotThereSaysItCouldNotBeRead() {
        let missing = URL(fileURLWithPath: "/nowhere/\(UUID().uuidString).csv")
        let refusal = DataFileCheck.refusal(of: missing)
        #expect(refusal?.contains("was not added") == true)
    }
}

/// The words beside the export sheet's bar (#668).
@Suite("Export progress (#668)")
struct ExportProgressSentenceTests {
    @Test func itSaysHowManyFramesOfHowMany() {
        let progress = ExportProgress(fraction: 0.35, framesWritten: 210, currentTime: 7, totalFrames: 600)
        #expect(progress.sentence == "Exporting… 210 of 600 frames")
        // The last frame can land one past a total rounded from the length.
        let last = ExportProgress(fraction: 1, framesWritten: 601, currentTime: 20, totalFrames: 600)
        #expect(last.sentence == "Exporting… 600 of 600 frames")
    }

    @Test func withoutATotalItSaysTheCountAsBefore() {
        #expect(ExportProgress(fraction: 0.5, framesWritten: 42, currentTime: 1).sentence == "Exporting… 42 frames")
    }
}
