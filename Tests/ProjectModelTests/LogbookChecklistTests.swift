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

    @Test func theDayToNameIsTheNewestSessionWithNoCar() {
        let entries = [Self.entry("a", month: 3), Self.entry("b", month: 8), Self.entry("c", car: "GR86", month: 10)]
        #expect(LogbookChecklist.sessionWithoutCar(in: entries)?.file.contentHash == "b")
        #expect(LogbookChecklist.sessionWithoutCar(in: [Self.entry("d", car: "Miata")]) == nil)
    }
}
