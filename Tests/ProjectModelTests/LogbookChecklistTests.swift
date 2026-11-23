import Foundation
import Testing

@testable import ProjectModel

@Suite("The Logbook's Getting Started (#452)")
struct LogbookChecklistTests {
    static func entry(_ hash: String, car: String = "", month: Int = 9) -> LogbookEntry {
        LogbookEntry(
            file: .init(path: "/d/\(hash).csv", contentHash: hash, byteCount: 1, importerID: "x"),
            date: Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: month, day: 1)),
            car: car)
    }

    @Test func anEmptyLogbookHasEverythingAhead() {
        let empty = LogbookChecklist(entries: [], coached: false, sawProgress: false)
        #expect(!empty.hasSessions && !empty.carsNamed && !empty.madeVideo && !empty.coached)
        #expect(!empty.isComplete)
    }

    @Test func eachStepIsReadFromTheLogbookWhereItCanBe() {
        var made = Self.entry("a", car: "Miata")
        made.projects = [.init(path: "/p/a.onboardproj", name: "a")]
        var coachedEntry = Self.entry("b", car: "Miata")
        coachedEntry.coaching = CoachingSettings(dataInputID: InputID(coachedEntry.id))
        let partway = LogbookChecklist(entries: [made, Self.entry("c")], coached: false, sawProgress: false)
        #expect(partway.hasSessions)
        #expect(!partway.carsNamed, "a session with no car")
        #expect(partway.madeVideo)
        #expect(!partway.coached)

        let all = LogbookChecklist(entries: [made, coachedEntry], coached: false, sawProgress: true)
        #expect(all.carsNamed && all.coached)
        #expect(all.isComplete)
        // Coaching opened from the Logbook counts though the session kept no choices.
        #expect(LogbookChecklist(entries: [made], coached: true, sawProgress: true).isComplete)
    }

    /// #667: the step stayed open after a video had been exported, because only a project saved
    /// before its data file was added was ever listed on a session.
    @Test func anExportedVideoIsAVideoMadeWhetherOrNotItsProjectWasSaved() {
        var exported = Self.entry("a", car: "Miata")
        exported.exports = [.init(path: "/v/a.mp4", name: "a.mp4")]
        #expect(LogbookChecklist(entries: [exported], coached: false, sawProgress: false).madeVideo)
        #expect(!LogbookChecklist(entries: [Self.entry("b")], coached: false, sawProgress: false).madeVideo)
    }

    /// #667: the Circuit column showed the file's name for a session that names no circuit.
    @Test func aSessionThatNamesNoCircuitHasNoneToList() {
        let unnamed = Self.entry("morning-log")
        #expect(unnamed.circuitTitle == "morning-log", "still what the session is called")
        #expect(unnamed.namedCircuit.isEmpty)
        var named = Self.entry("b")
        named.trackName = "Thunderhill"
        #expect(named.namedCircuit == "Thunderhill")
        named.configuration = "West"
        #expect(named.namedCircuit == named.circuitTitle && named.namedCircuit.contains("West"))
        // A car park nobody named is called by its course, as the sidebar lists it.
        var run = Self.entry("c")
        run.course = CourseTag(name: "Course of 12 Oct 2026")
        #expect(run.namedCircuit == run.circuitTitle && !run.namedCircuit.isEmpty)
    }

    @Test func theDayToNameIsTheNewestSessionWithNoCar() {
        let entries = [Self.entry("a", month: 3), Self.entry("b", month: 8), Self.entry("c", car: "GR86", month: 10)]
        #expect(LogbookChecklist.sessionWithoutCar(in: entries)?.file.contentHash == "b")
        #expect(LogbookChecklist.sessionWithoutCar(in: [Self.entry("d", car: "Miata")]) == nil)
    }
}
