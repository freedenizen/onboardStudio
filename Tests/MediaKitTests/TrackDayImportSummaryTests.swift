import Foundation
import ProjectModel
import Testing

@testable import MediaKit

/// What the Add Files report says in its first line and of each file (#665).
@Suite("Add Files report (#665)")
struct TrackDayImportSummaryTests {
    private func entry(_ name: String, at date: Date? = nil) -> LogbookEntry {
        var entry = LogbookEntry(
            file: .init(path: "/day/\(name)", contentHash: name, byteCount: 1, importerID: "x"), car: "")
        entry.date = date
        entry.trackName = "Test Circuit"
        return entry
    }

    private func added(_ name: String) -> TrackDayImport.Report {
        TrackDayImport.Report(url: URL(fileURLWithPath: "/day/\(name)"), outcome: .added(entry(name)))
    }

    /// A recording: the picture of a logger's session, or — `madeSession` — read as its own.
    private func clip(_ name: String, madeSession: Bool = false, at date: Date? = nil) -> TrackDayImport.Report {
        let record = ClipRecord(path: "/day/\(name)", byteCount: 1, fingerprint: name)
        return TrackDayImport.Report(
            url: URL(fileURLWithPath: "/day/\(name)"), outcome: .clip(record, session: entry(name, at: date)),
            madeSession: madeSession)
    }

    @Test func theSessionsCountedAreTheOnesTheTableThenShows() {
        // Six logger files, six recordings of them, and three recordings with no logger session:
        // nine sessions in the table, where the line used to say six.
        var reports = (1...6).map { added("log\($0).csv") }
        reports += (1...6).map { clip("GX01000\($0).MP4") }
        reports += (7...9).map { clip("GX01000\($0).MP4", madeSession: true) }
        #expect(
            TrackDayImport.summary(of: reports, onChosenDay: false)
                == "9 sessions added, 3 of them from camera recordings with no logger session, 9 clips.")
        #expect(reports.compactMap(\.addedEntry).count == 9)
    }

    @Test func recordingsAloneAreSessionsToo() {
        let one = [clip("GX010001.MP4", madeSession: true)]
        #expect(
            TrackDayImport.summary(of: one, onChosenDay: false)
                == "1 session added, from a camera recording with no logger session, 1 clip.")
        let two = one + [clip("GX010002.MP4", madeSession: true)]
        #expect(
            TrackDayImport.summary(of: two, onChosenDay: false)
                == "2 sessions added, from camera recordings with no logger session, 2 clips.")
    }

    @Test func theRestOfTheLineIsAsItWas() {
        #expect(TrackDayImport.summary(of: [], onChosenDay: false) == "Nothing in those files that this app reads.")
        let reports = [
            added("a.csv"), clip("a.MP4"),
            TrackDayImport.Report(url: URL(fileURLWithPath: "/day/b.csv"), outcome: .alreadyThere(entry("b.csv"))),
            TrackDayImport.Report(url: URL(fileURLWithPath: "/day/notes.csv"), outcome: .notRecognised),
        ]
        #expect(
            TrackDayImport.summary(of: reports, onChosenDay: false)
                == "1 session added, 1 clip, 1 already in the logbook, 1 not read.")
    }

    @Test func aRecordingReadAsItsOwnSessionSaysSoAndWhenItBegan() {
        let began = Date(timeIntervalSince1970: 1_700_000_000)
        let time = began.formatted(date: .abbreviated, time: .shortened)
        let own = clip("GX010007.MP4", madeSession: true, at: began).line
        #expect(own.contains("no logger session at that time, so a session of its own"))
        #expect(own.contains(time), "two sessions of a day are told apart by when they began")
        let picture = clip("GX010001.MP4", at: began).line
        #expect(picture.contains("the picture of") && picture.contains(time))
        #expect(clip("GX010001.MP4").addedEntry == nil, "a session's picture adds no session")
    }

    @Test func anEmptyVideoIsSaidToBeEmptyAndWhatToDo() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "empty-clip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let empty = folder.appending(path: "GX010001.MP4")
        try Data().write(to: empty)
        let logbook = Logbook(directory: folder.appending(path: "logbook"))
        let reports = await TrackDayImport.run([empty], into: logbook)
        let line = try #require(reports.first).line
        #expect(line == "GX010001.MP4 — could not be read: the file is empty; copy it from the camera's card again")
        #expect(logbook.entries().isEmpty && logbook.days().isEmpty)
    }

    @Test func progressSaysWhichFileOfHowMany() {
        let step = TrackDayImport.Step(index: 2, count: 20, name: "session_3.csv")
        #expect(step.sentence == "Reading 3 of 20: session_3.csv…")
    }
}
