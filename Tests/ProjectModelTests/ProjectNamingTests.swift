import Foundation
import Testing

@testable import ProjectModel

@Suite("What a project is called before it is saved (#481, #467)")
struct ProjectNamingTests {
    /// The Logbook's own way of writing a day, whatever this Mac's language.
    private func day(_ iso: String) throws -> String { try #require(ProjectDetails.displayDate(iso)) }

    @Test func aSessionIsCalledAsTheLogbookListsIt() throws {
        let date = try #require(ProjectDetails.day("2026-09-22"))
        #expect(ProjectNaming.name(title: "Sonoma Raceway", date: date) == "Sonoma Raceway, \(try day("2026-09-22"))")
        // A session whose day is unknown is its circuit alone.
        #expect(ProjectNaming.name(title: "Sonoma Raceway", date: nil) == "Sonoma Raceway")
    }

    @Test func otherwiseTheDetailsSayWhereAndWhen() throws {
        let both = ProjectDetails(track: "Sonoma Raceway", car: "GR86", date: "2026-08-23")
        #expect(ProjectNaming.name(details: both) == "Sonoma Raceway, \(try day("2026-08-23"))")
        #expect(ProjectNaming.name(details: ProjectDetails(track: " Laguna Seca ")) == "Laguna Seca")
        #expect(ProjectNaming.name(details: ProjectDetails(date: "2026-08-23")) == (try day("2026-08-23")))
        // The car, the driver or a date that is not one do not name a project: it stays Untitled.
        #expect(ProjectNaming.name(details: ProjectDetails(car: "GR86", driver: "Alex")) == nil)
        #expect(ProjectNaming.name(details: ProjectDetails(track: "Thunderhill", date: "August")) == "Thunderhill")
        #expect(ProjectNaming.name(details: ProjectDetails()) == nil)
    }

    @Test func aSecondProjectOfTheSameNameIsNumbered() {
        let name = "Sonoma Raceway, Sep 22, 2026"
        #expect(ProjectNaming.numbered(name, taken: []) == name)
        #expect(ProjectNaming.numbered(name, taken: ["Untitled", name]) == "\(name) 2")
        #expect(ProjectNaming.numbered(name, taken: [name, "\(name) 2"]) == "\(name) 3")
        // A gap is filled, as Untitled's numbers are.
        #expect(ProjectNaming.numbered(name, taken: [name, "\(name) 3"]) == "\(name) 2")
    }

    @Test func aNameBecomesAFileName() {
        #expect(ProjectNaming.fileName("Sonoma Raceway, Sep 22, 2026") == "Sonoma Raceway, Sep 22, 2026")
        #expect(ProjectNaming.fileName("Club Day 2/3: Sonoma") == "Club Day 2-3- Sonoma")
        #expect(ProjectNaming.fileName("  ") == "Untitled")
    }
}
